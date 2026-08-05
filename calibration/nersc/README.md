# NERSC 部署 (单节点 + 常驻 parpool)

Windows/WSL 那套 (`controller.py` + tmux + `run_leg.sh`) 在 NERSC 上不用。
这里换成: **一个作业 = 一个常驻 MATLAB = 一个 parpool**, 跨代复用, 不反复拉起
MATLAB 进程, license 只占 1 席 + 1 个 PCT。

```
submit.sh                 sbatch 入口, 墙钟到点(提交由你手动做, 可一次排多个)
run_generation.m          常驻驱动: 代循环 / parfeval 撒腿 / 抽指标 / 判成功 / 调 CMA
run_leg_worker.m          worker 侧单腿包装 (永不抛异常, 单线程, 独立 prefdir)
gen_tool.py               propose / success / report / penalize —— MATLAB 用 system() 调
```

CMA-ES 本身 (`../optimizer/propose_cmaes.py`, vendored pycma) 原样复用, 只把
population 改成读 `CALIB_POPULATION`。

## 一次代循环

1. `gen_tool.py propose N` → CMA ask, 写 `calibration/state.json` 的 `batchNN_cases`
   (幂等: pending 命中则原样重发, 不会重复推进一代)
2. MATLAB `jsondecode` 读 cases → 每个 case 3 个 dose → `parfeval` 提交
   (默认 30 case × 3 = 90 条腿, 一次全撒)
3. 腿完成 → 逐 case `extract_calibration_metrics`
4. `gen_tool.py success N` → 命中则写 `calibration/DONE` 并停; 否则回到 1 提议 N+1
   (提议 N+1 时 CMA 自动 tell 第 N 代的全部 fitness)

## 上线前必做

1. **改项目号**: `submit.sh` 的 `#SBATCH -A m0000`。
2. **量一条腿**: 先交互式跑一条,拿到 wall time 和峰值内存,再定 `CALIB_WORKERS`。
   ```bash
   salloc -N 1 -C cpu -q interactive -t 2:00:00 -A <acct>
   module load matlab && cd $CALIB_REPO_DIR
   /usr/bin/time -v matlab -nodisplay -batch \
     "run_calibration_case('probe',3,ones(1,10))"
   ```
   90 worker × 峰值内存必须 < 节点内存 (Perlmutter CPU 节点 512 GB)。超了就降
   `CALIB_WORKERS`(腿会分批跑,代时间变长但不会失败)。
3. **一条腿的时长决定 walltime**: 若单腿 > (walltime − 余量), 腿会靠 checkpoint
   跨作业续算,每代要多个作业才完成 —— 能跑通,只是慢。`-t` 尽量取队列上限。
4. **首次冷启动**: 仓库里不要有 `calibration/state.json`; 第一次 propose 会自己建。

## 运行 (提交由你手动做, 脚本可反复提交)

```bash
export CALIB_REPO_DIR=$SCRATCH/matfdmcali
sbatch calibration/nersc/submit.sh                                # 交一个
for i in 1 2 3 4; do sbatch calibration/nersc/submit.sh; done     # 一次排四个, 串行接力
```

`--dependency=singleton` + 同一个作业名 `matfdm_cal` 保证**同时只有一个在跑**,
后面的在队列里等前一个结束再自动接上。每个作业启动时从磁盘状态续:CMA 从
`cma_state.pkl`(丢了就用 metrics 重放全部历史), 未完成的腿从 checkpoint,
已完成的腿跳过。命中后写 `calibration/DONE`, 队列里剩下的作业见到它就空转退出。

代码侧**不设任何时限**: 驱动和腿都不自我限时, 墙钟到点由 SLURM 直接杀,
最多损失当前那个 checkpoint 窗口(每腿 50 窗)。想让它提前收手才设
`CALIB_WALL_BUDGET`。

监控:
```bash
tail -f matfdm_cal-*.out                          # 代/腿级进度
python3 calibration/nersc/gen_tool.py report 3    # 第 3 代每个 case 的前沿
cat calibration/optimizer/fitness_history.csv     # 全历史 fitness
```

停止: `touch $CALIB_REPO_DIR/calibration/STOP` (队列里没跑的作业会空转退出)。

## 容错

| 情况 | 处理 |
|---|---|
| 墙钟耗尽(SLURM 硬杀) | 最多损失当前 checkpoint 窗口; 下一个作业从 checkpoint 续算 |
| 作业被抢占/节点故障 | 同上, checkpoint 是 tmp+rename 原子写 |
| 单腿 MATLAB 报错 | worker try/catch, 写 `calibration/logs/<tag>_dose<d>_error.log`, 下一个作业重试 |
| 同一腿连续失败 ≥3 次 | `gen_tool.py penalize` 给该 case 写"最差且不可行"指标, CMA 排它到末位继续推进, **不卡整代** |
| 已完成的腿被重跑 | `run_calibration_case` 开头的幂等守卫直接 return |

## 与 Windows 版的差异

- 不用 tmux / 不用 `controller.py` / 不用 watchdog (SLURM + 续投链接管生死)
- 不用 `wslpath`, 无 5001/ServiceHost/文件可见性延迟那套 Windows 特化逻辑
- `CALIB_KEEP_TRAJ=0` 跳过 `fields_timeseries.mat`/`irr_timeseries.mat`
  (每腿 ~7 MB × 90 腿/代, 标定不读它们)
- 腿之间靠 **process worker + case_tag 分目录** 隔离: 各自独立进程,
  `decouple/<tag>/dose*` 与 `checkpoint/<tag>/` 互不重叠

## 本次一并修掉的既有问题

- `propose_cmaes.py`: 冷启动 (state.json 无 `optimizer` 键) 必然 `KeyError` ——
  赋值语句先求右侧, 原写法 `state.setdefault(...)[...] = state["optimizer"]...` 顺序反了
- `run_ckpt_decouple.m`: 两处 `exit(0)` 会杀掉常驻 MATLAB → 加 `CALIB_NO_EXIT` 守卫
- `extract_calibration_metrics.m`: 写死 `zeros(150,4)` / `trapz(0:149,...)` →
  改成按文件实际长度, `p.ny` 变了不会静默出错
- `run_calibration_case.m`: 无幂等守卫, 续投会重跑已完成的腿
