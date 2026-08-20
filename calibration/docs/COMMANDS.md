# matfdm 标定 — 命令速查

## 结构

```
代码 (只读, 一份)                        数据 ($SCRATCH/matfdm_runs/<id>/)
matfdm/                                  <id>/
├── build_p_decouple.m  基线参数           ├── config.json        唯一配置源
├── rhs_aks.m …         物理                ├── provenance.txt     commit + 配置快照
├── run_root.m          数据根解析          ├── decouple/<case>/dose<d>/
├── read_run_config.m   读 config.json      ├── checkpoint/<case>/
└── calibration/                           └── calibration/
    ├── ctl/            控制器与工具            ├── metrics/<case>.csv
    │   ├── matfdm.sh       总入口              ├── state.json
    │   ├── multi_node.sh   N 节点作业          ├── optimizer/  CMA pickle+历史
    │   ├── node_task.sh    单节点任务          ├── logs/       每条腿 diary
    │   ├── single_node.sh  单节点作业          └── DONE / STOP
    │   ├── run_generation.m   常驻驱动
    │   ├── run_leg_worker.m   腿包装
    │   ├── gen_tool.py        代级助手
    │   ├── show_best.py       排名+参数
    │   ├── rescore_best.py    换标尺后重算
    │   └── patch_objective.py 目标函数补丁
    ├── optimizer/      CMA-ES
    ├── vendor/         pycma
    └── docs/           本文件
```

**隔离**:`MATFDM_RUN` 指到哪,数据写到哪。代码目录永远只读,多个运行/多个节点互不可见。
**配置**:改 `config.json`,不改源码。`overrides` 里的字段在 `build_p_decouple` 之后覆盖到 `p`。
**指纹**:`params.txt` 含乘子+基线+全部关键标量,改任何物理量旧腿自动作废重算。

## 前置

```bash
export MATFDM_CODE=$SCRATCH/projects/matfdm     # 代码目录
export MATFDM_RUNS=$SCRATCH/matfdm_runs         # 数据根 (默认值同此)
export MATFDM_ACCOUNT=m5181                     # 账号
alias mf='bash $MATFDM_CODE/calibration/ctl/matfdm.sh'
```

## 多节点(主用法)

```bash
# 1) 批量建运行: 30 个前沿阈值
mf sweep front_thick "0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0 1.1 1.2 1.3 1.4 1.5 \
                      1.6 1.7 1.8 1.9 2.0 2.2 2.4 2.6 2.8 3.0 3.5 4.0 4.5 5.0 6.0 8.0" ft

# 2) 生成清单 (每行一个运行目录, 第 k 行给第 k 个节点)
mf list 'ft*' > $MATFDM_RUNS/runs_ft.txt

# 3) 一个作业占 30 节点, 排 4 轮接力 (afterany 链, 断点续算)
mf launch $MATFDM_RUNS/runs_ft.txt 4
```

`launch` 会按清单行数自动定 `-N`。作业名 `mn_<清单名>`,链式依赖保证前一轮结束后一轮再上。
单节点崩掉不影响其他节点(`--kill-on-bad-exit=0`,`node_task.sh` 永远 exit 0)。

扫别的量一样:

```bash
mf sweep overrides.eff "0.05 0.1 0.15 0.2 0.25 0.3" eff
mf sweep middle_max "60 65 70 75" mm
mf sweep overrides.Dgb "1e-4 5e-4 1e-3 5e-3" dgb
mf list 'eff*' > $MATFDM_RUNS/runs_eff.txt && mf launch $MATFDM_RUNS/runs_eff.txt 4
```

任意组合手工写清单也行,一行一个运行目录即可。

## 单节点(调试/单变体)

```bash
mf new base                         # 用默认 config
mf new base front_thick=0.5 population=40 overrides.eff=0.2
mf submit base 4                    # 排 4 个单节点接力作业
```

## 看进度

| 目的 | 命令 |
|---|---|
| 全部运行总览 | `mf status` |
| 某个运行的 CMA 状态 | `mf status ft05` |
| 前十名+参数绝对值 | `mf best ft05 10` |
| 排名(现算, 不读快照) | `MATFDM_RUN=$MATFDM_RUNS/ft05 python3 $MATFDM_CODE/calibration/ctl/gen_tool.py rank --top 20` |
| 某代逐 case | `MATFDM_RUN=… gen_tool.py report 12` |
| 某 case 三行指标 | `column -s, -t $MATFDM_RUNS/ft05/calibration/metrics/b12_c07_cma.csv` |
| 多节点作业总日志 | `tail -f $MATFDM_RUNS/mn_runs_ft-*.out` |
| 某节点的日志 | `tail -f $MATFDM_RUNS/ft05/node-*-r*.log` |
| 某条腿跑到第几窗 | `tail -3 $MATFDM_RUNS/ft05/calibration/logs/b12_c07_cma_dose3.log` |
| 队列 | `squeue --me -o "%.10i %.12j %.6D %.8T %.9M %.20R"` |

`fitness_history.csv` 与 `cma_generation.json` 是**上一次 propose 的快照**;改过目标函数要用 `rank` / `best` 现算,或等下一代刷新。

## 停/续/清

```bash
mf stop ft05          # 写 STOP, 该运行的节点空转退出
mf resume ft05
mf clean ft05         # 清数据保留 config.json
scancel --me -n mn_runs_ft      # 取消整个多节点作业链
```

## 改配置 / 改判据

改 `config.json` 后**不需要动代码**,下一个作业自动生效;涉及物理的改动会通过指纹让旧腿重算。

```bash
vi $MATFDM_RUNS/ft05/config.json         # front_thick / targets / overrides.eff / …
mf new ft05 front_thick=0.75             # 或者用 new 增量改 (幂等, 保留已有字段)
```

改目标函数(全局,影响所有运行):

```bash
python3 $MATFDM_CODE/calibration/ctl/patch_objective.py     # 幂等
MATFDM_RUN=$MATFDM_RUNS/ft05 CALIB_POPULATION=40 \
  python3 $MATFDM_CODE/calibration/ctl/rescore_best.py      # 每个运行各跑一次
```

**时机**:改 `cma_state.pkl` 的操作要在两次 propose 之间做——看到 `[gen NN] … legs` 之后最安全。

## config.json 字段

| 字段 | 默认 | 说明 |
|---|---|---|
| `run_id` | 目录名 | 标识 |
| `doses` / `targets` | `[0,0.5,3]` / `[40,60,100]` | 剂量与靶深度 nm |
| `front_thick` | 1.0 | 前沿判据: 总氧化物厚度 nm |
| `population` / `workers` | 40 / 120 | 每代 case 数 / parpool worker 数 |
| `middle_max` | 70 | 0.5 dpa 软带上限 nm |
| `endpoint_band` | 5 | 端点硬约束 nm (超出即不可行) |
| `endpoint_tol` | 3 | 成功判据端点容差 nm |
| `max_attempts` | 3 | 腿失败几次后熔断该 case |
| `keep_traj` | false | 是否存 `*_timeseries.mat` (每腿 ~7 MB) |
| `seed` | 20260804 | CMA 随机种子 (多链要给不同值) |
| `overrides` | `{}` | 覆盖 `p` 的任意字段: `eff`、`Dgb`、`Ks`、`rOM`… |

## 故障对照

| 现象 | 处理 |
|---|---|
| 节点空转 "清单里没有第 k 行" | 清单行数少于 `-N`,正常;`launch` 会自动按行数定节点数 |
| 秒退 "已命中且仍达标" | 真命中;想继续优化就收紧 `middle_max` 或删 `DONE` |
| 秒退 "STOP 存在" | `mf resume <id>` |
| `future feature annotations` | 用了 /usr/bin/python3 (3.6);`module load python` |
| `CMA-ES 提议失败` | 看日志里紧跟的 python 报错;缺指标会自动 `penalize-missing` 重试 |
| parpool 停住 | 120 worker 起来要 5–6 分钟;超 10 分钟查 `pgrep -c -u $USER -f MATLAB` |
| 某腿反复失败 | 3 次后熔断;错误在 `<run>/calibration/logs/<tag>_dose<d>_error.log` |
