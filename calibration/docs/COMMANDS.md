# matfdm 标定 — 操作手册

**引擎是编译版 MATLAB Runtime,占用 0 个 MATLAB / 0 个 PCT 席位。**
NERSC 全校只有 16 个 MATLAB 和 4 个 PCT 席位,文档明确要求多节点作业跑编译版
([docs](https://docs.nersc.gov/applications/matlab/#parallelism-with-the-matlab-compiler))。
老的 `matlab -batch` + parpool 路线仍可用(`MATFDM_ENGINE=matlab`),但要抢 license,
只在调试时用。

```bash
alias mf='bash $SCRATCH/projects/matfdm/calibration/ctl/matfdm.sh'
export MATFDM_CODE=$SCRATCH/projects/matfdm
```

---

## 一、编译(只在改了 .m 源码时做)

**必须在计算节点上编**,不要在 login 节点(无图形时 `mcc` 会 segfault)。
编译本身要签一个 MATLAB + 一个 Compiler 席位,几分钟,一次性。

```bash
salloc -N 1 -q interactive -C cpu -t 00:30:00 -A m5181
bash $MATFDM_CODE/calibration/ctl/build_standalone.sh
```

不在交互 shell 里时:

```bash
srun --jobid=<交互作业号> -N1 -n1 --overlap -c 32 \
     bash $MATFDM_CODE/calibration/ctl/build_standalone.sh
```

产物(带 git commit,不进 git):

```
$SCRATCH/matfdm_build/
├── CURRENT -> <commit>/            作业默认用这个
└── <commit>/
    ├── matfdm_run                  standalone
    ├── run_matfdm_run.sh           启动脚本
    ├── baseline.json               十个基线快照 (后处理对齐用)
    └── BUILD_COMMIT
```

验证编译产物:

```bash
srun --jobid=<作业号> -N1 -n1 --overlap \
     bash $MATFDM_CODE/calibration/ctl/matfdm_mcr.sh selftest $SCRATCH/matfdm_runs/ft4e-1
```

看到 `isdeployed : 1` 和 `=== selftest OK ===` 就是通了。

### 什么时候必须重编

| 改什么 | 要重编吗 |
|---|---|
| CMA 给的乘子、`config.json` 全部字段 | ❌ 运行时读 |
| 物理参数走 `overrides`(`eff`/`Dgb`/`DV`/`f0I`…) | ❌ 运行时读 |
| 新增/删除变体、换扫描字段与值 | ❌ 只是新建运行目录 |
| 目标函数、CMA 设置(`propose_cmaes.py`、`patch_objective.py`、`gen_tool.py`) | ❌ 是 Python,不在 CTF 里 |
| 实验成分靶值（`Composition_Dose.csv`） | ❌ `comp_targets.py` 现算，写进 config |
| `build_p_decouple.m` 的基线值 | ✅ 是源码（密度/分子量也在里面，抽指标时从它读）|
| `rhs_aks.m` 等方程、`run_calibration_case.m`、网格/时长逻辑 | ✅ 是源码 |

改了源码没重编,`baseline.json` 里的 `build_commit` 会和当前 commit 对不上,
后处理会打印出来。

---

## 二、提交作业

**所有设置都在 `calibration/ctl/JOB.sh` 顶部的设置区里,改完直接跑:**

```bash
cd $SCRATCH/projects/matfdm
vi calibration/ctl/JOB.sh        # 改设置区
bash calibration/ctl/JOB.sh      # 建运行目录 + 生成清单 + 提交作业链
```

### JOB.sh 设置区

```bash
ACCOUNT=m5181                 # SLURM 账号
WALLTIME=08:00:00             # 每个作业的墙钟
NJOBS=20                      # 排几轮接力 (afterany 链, 断点续算)
QOS=regular                   # regular / debug / preempt

CODE=$SCRATCH/projects/matfdm # 代码目录 (只读)
RUNS=$SCRATCH/matfdm_runs     # 数据根

SWEEP_KEY=front_thick         # 要扫的字段
SWEEP_VALUES="0.1 0.2 ... 1.0"    # 每个值一个运行, 一个运行占一个节点
PREFIX=ft                     # 目录名前缀 -> ft1e-1, ft5e-1, ft1e0 ...

POPULATION=40                 # 每代 case 数
WORKERS=120                   # 同时跑几条腿 (= POPULATION × 剂量数)
DOSES="[0, 0.5, 3]"
TARGETS="[40, 60, 100]"
MIDDLE_MAX=70                 # 0.5 dpa 软带上限 nm
ENDPOINT_BAND=5               # 端点硬约束 nm
ENDPOINT_TOL=3                # 成功判据端点容差 nm
MAX_ATTEMPTS=3
KEEP_TRAJ=false
SEED=20260804

OVERRIDES='{"eff": 0.2}'      # 物理参数覆盖, 不改源码也不用重编
```

**节点数 = `SWEEP_VALUES` 的个数**,`JOB.sh` 自动算,不用手填 `-N`。

提交前 `JOB.sh` 会检查编译产物在不在、运行名有没有撞、已存在目录里记的值对不对得上,
任一不过就一个作业都不提交。

### 常见几种扫描

```bash
SWEEP_KEY=front_thick   ; SWEEP_VALUES="0.25 0.5 0.75 1.0 1.5 2.0" ; PREFIX=ft
SWEEP_KEY=overrides.eff ; SWEEP_VALUES="0.05 0.1 0.15 0.2"          ; PREFIX=eff
SWEEP_KEY=overrides.Dgb ; SWEEP_VALUES="1e-4 5e-4 1e-3 5e-3"        ; PREFIX=dgb
SWEEP_KEY=middle_max    ; SWEEP_VALUES="60 65 70 75"                ; PREFIX=mm
SWEEP_KEY=seed          ; SWEEP_VALUES="101 202 303 404 505"        ; PREFIX=seed
```

### 单个运行(调试用)

```bash
mf new test front_thick=0.5 population=40 overrides.eff=0.2
mf submit test 2                 # 2 个单节点接力作业
```

### 交互节点验证(不占正式机时)

```bash
salloc -N 3 -q interactive -C cpu -t 01:00:00 -A m5181
export MATFDM_CODE=$SCRATCH/projects/matfdm
export MATFDM_MANIFEST=$SCRATCH/matfdm_runs/runs_ft.txt
bash $MATFDM_CODE/calibration/ctl/multi_node.sh
```

每个节点日志里出现 `[gen 01] 40 cases x 3 dose = 120 legs` 就是通了。

---

## 三、改参数

`config.json` 是唯一真相源,改完下一个作业自动生效,**不用重编、不用动代码**。
涉及物理的改动会通过参数指纹让旧腿自动作废重算。

```bash
vi $SCRATCH/matfdm_runs/ft5e-1/config.json
mf new ft5e-1 front_thick=0.75          # 或增量改 (幂等, 保留其他字段)
```

物理参数一律走 `overrides`,它在 `build_p_decouple` 之后逐字段覆盖到 `p`,
任意字段都能盖,数组也行:

```bash
mf new ft5e-1 'overrides={"eff":0.2,"DV":[1e7,7e6,5e6,9e6],"f0I":0.44}'
```

改目标函数(全局,纯 Python,不用重编):

```bash
python3 $MATFDM_CODE/calibration/ctl/patch_objective.py            # 幂等
MATFDM_RUN=$SCRATCH/matfdm_runs/ft5e-1 CALIB_POPULATION=40 \
  python3 $MATFDM_CODE/calibration/ctl/rescore_best.py             # 每个运行各跑一次
```

**时机**:改 `cma_state.pkl` 的操作(rescore/patch)要在两次 propose 之间做——
看到 `[gen NN] … legs` 之后最安全,不用停作业。

### config.json 字段

| 字段 | 默认 | 说明 |
|---|---|---|
| `run_id` | 目录名 | 标识 |
| `doses` / `targets` | `[0,0.5,3]` / `[40,60,100]` | 剂量与靶深度 nm |
| `front_thick` | 1.0 | 前沿判据: 总氧化物厚度 nm |
| `population` / `workers` | 40 / 120 | 每代 case 数 / 同时跑几条腿 |
| `middle_max` | 70 | 0.5 dpa 软带上限 nm |
| `endpoint_band` | 5 | 端点硬约束 nm (超出即不可行) |
| `endpoint_tol` | 3 | 成功判据端点容差 nm |
| `max_attempts` | 3 | 腿失败几次后熔断该 case |
| `leg_timeout` | 0（不限）| 单腿**累计**计算时限 s；超时即判这组乘子不收敛，丢弃整个 case |
| `keep_traj` | false | 是否存 `*_timeseries.mat` (每腿 ~7 MB) |
| `seed` | 20260804 | CMA 种子 (多链要给不同值) |
| `composition_targets` | 由 csv 现算 | 实验成分靶值 `[[Cr%,Fe%], ...]`，每个剂量一对 |
| `composition_tol` | 5 | 成分命中容差 at%（Cr 和 Fe 都要落在带内）|
| `composition_scale` | 3 | 成分残差标尺 at%，越小权重越高；3 = 与前沿端点等权 |
| `overrides` | `{}` | 覆盖 `p` 的任意字段 |

---

### 标定指标：前沿位置 + 成分

标定同时盯两件事，两者都进 `residual`：

| 指标 | 靶值来源 | 权重 |
|---|---|---|
| 前沿深度 nm | `config.json` 的 `targets` | 端点 `Δ/3`，0.5 dpa 带内 `Δ/6` |
| 成分 at% | `Composition_Dose.csv` → `composition_targets` | `Δ/composition_scale`，默认 `/3` |
| Cr 随剂量的趋势 | 无（定性先验）| 单边惩罚：`max(0, Cr↑)/2`，趋势对了为 0 |

`composition_scale` **越小成分权重越高**。前沿端点是 `/3`，所以默认 3 = 成分与前沿端点
等权；设 5 则成分只有前沿的 0.6 倍。改它不用重编。

**Cr 随剂量单调下降是单边惩罚**，趋势对了不花钱，反了才罚。靶值本身确实蕴含这个趋势
（75.2 > 68.3 > 57.8），但那要到靶值附近才体现；离靶还有二三十 at% 时靶值残差对趋势
的约束很弱，一个 Cr 反着涨的样本照样可能因为前沿好而排前面，把 CMA 带偏。这一项负责
在早期把搜索方向摆正。

另外两条同批删掉的旧约束**不恢复**：`Cr-Fe ≤ 15`（靶值处是 19.53，留着等于让实验靶值
自己不可行）、`Cr > Si`（Si 已从原子计数分母里去掉，现在只是诊断比值）。

成分口径：**分母 = Cr+Fe+Ni**。SiO2 会溶解，不占氧化物金属份额；Ni 留在分母里
是为了和实验同口径。因为模型不产 Ni（Ni≡0），模型的 Cr%+Fe% 恒为 100%，而实验只有
99.1/97.6/96.1%，所以**成分残差有 0.87/2.38/3.94 at% 的地板，fitness 不会收敛到零**。
这是这个口径的固有属性 —— 好处是 Ni 的缺失被如实记在账上，不会被归一化抹掉。

```bash
python3 calibration/ctl/comp_targets.py                 # 看靶值表
python3 calibration/ctl/comp_targets.py --basis crfe    # 换成把 Ni 归一化掉的口径
```

换实验数据只要换 `Composition_Dose.csv`；换口径只要改 `JOB.sh` 的 `COMPOSITION_BASIS`。
**两者都不用重编** —— 模型 Ni≡0，所以 MATLAB 算的 `Cr/(Cr+Fe+Ni)` 与 `Cr/(Cr+Fe)` 恒等，
口径差别全在 config 里的靶值上。

硬约束只剩两类：Cr 库存随剂量单调下降、端点前沿落在 `endpoint_band` 内。成分**不进硬约束**：
有那个地板在，任何“成分必须多准”的硬门槛都会把整代样本一次判成不可行，CMA 就没排序信息了。

---

## 四、看进度

| 目的 | 命令 |
|---|---|
| 全部运行总览 | `mf status` |
| 某运行的 CMA 状态 | `mf status ft5e-1` |
| 前十名 + 参数绝对值 + 成分残差 | `mf best ft5e-1 10` |
| 每个运行各导一份前十名 txt | `mf export 'ft*' 10` |
| 队列 | `squeue --me -o "%.10i %.12j %.6D %.8T %.9M %.20R"` |
| 多节点作业总日志 | `tail -f $SCRATCH/matfdm_runs/mn_ft-*.out` |
| 某节点日志 | `tail -f $SCRATCH/matfdm_runs/ft5e-1/node-<作业号>-*.log` |
| 全部节点的一代进度 | `grep -h '\[gen ' $SCRATCH/matfdm_runs/ft*/node-<作业号>-*.log \| tail -20` |
| 本次作业有没有超时判死 | `grep -h '\[timeout\]\|\[dead\]' $SCRATCH/matfdm_runs/ft*/node-<作业号>-*.log` |
| 某条腿跑到第几窗 | `tail -3 $SCRATCH/matfdm_runs/ft5e-1/calibration/logs/b12_c07_cma_dose3.log` |
| 某 case 三行指标 | `column -s, -t $SCRATCH/matfdm_runs/ft5e-1/calibration/metrics/b12_c07_cma.csv` |
| 排名(现算, 不读快照) | `MATFDM_RUN=…/ft5e-1 python3 $MATFDM_CODE/calibration/ctl/gen_tool.py rank --top 20` |
| **确认没占 license** | `ssh <node> 'ls -l /proc/*/exe 2>/dev/null \| grep -c R2023b/bin/glnxa64/MATLAB'` 应为 0 |
| 节点上的腿进程数 | `ssh <node> 'pgrep -c -u $USER -f matfdm_run'` 应为 `workers` |

**日志命令一律带上作业号。** `node-*.log` 会把历次作业的日志全匹配上 —— 一个运行目录
里累积着几十个作业的日志,不带作业号翻出来的多半是旧的。

`fitness_history.csv` 和 `cma_generation.json` 是**上一次 propose 的快照**;
改过目标函数要用 `rank` / `best` 现算,或等下一代刷新。

**时间参考**:MCR 冷启动 ~15 s、热启动 ~9 s;单腿约 1 h(独占节点约 17 min);
一代 1–1.5 h;8 h 作业约 6–8 代。120 条腿并发时节点内存峰值约 **215 GB / 503 GB**。

`dose3` 的腿比 `dose0`/`dose0.5` 长一截:它多一段辐照(参考约 5200 s),而辐照段
按设计**不存断点**,中断就整段重跑。所以一代里 dose3 总是最后收回。

---

## 五、后处理:每个运行的前十名导成 txt

```bash
mf export                       # 全部 ft*, 前十名 -> $SCRATCH/matfdm_runs/postprocess/
mf export 'ft*' 20              # 前二十名
mf export 'eff*' 10 ~/out       # 换前缀 / 换输出目录
```

| 参数 | 默认 | 说明 |
|---|---|---|
| `--pattern` | `ft*` | 运行目录通配 |
| `--top` | 10 | 每个运行取前几名 |
| `--out` | `<数据根>/postprocess` | 输出目录 |
| `--csv` | 关 | 顺带导一份同名 `.csv`（含逐剂量 Cr/Fe at%、Δ、`comp_max_abs_dev`）|

文件名 = 运行目录名(`ft1e-1.txt`、`ft5e-1.txt`…)。正文格式与 `mf best` 一致——
脚本是逐个运行去调 `show_best.py`,不另抄排版。判据取该运行自己的 `config.json`。

总表带一列 `成分|Δ|max`，是该运行第一名在三个剂量上 Cr/Fe 偏差的最大绝对值；
txt 正文里每个 case 都有一行 `成分残差 : ΔCr ... ΔFe ... 最大|Δ| ... 命中/超差`。

**排序按扫描值的数值**,不是目录名字典序(`ft1e0`=1 在字典序里会排到 `ft2e-1`=0.2 前面)。

---

## 六、停 / 续 / 清

```bash
mf stop ft5e-1                        # 该运行的节点空转退出
mf resume ft5e-1
mf clean ft5e-1                       # 清数据, 保留 config.json
touch $SCRATCH/matfdm_runs/ft*/calibration/STOP     # 全停
squeue --me -h -o "%i %j" | awk '$2 ~ /^mn_ft/ {print $1}' | xargs -r scancel
```

### 算不完的 case 怎么处理

腿卡住时,卡的是**单个时间窗内部的 ODE 求解** —— MATLAB 在窗与窗之间做的检查根本
轮不到,所以时限只能由编排器从外面计时并杀进程。`leg_timeout` 就是干这个的:

- 计时是**累计的**,记在 `<run>/calibration/leg_runtime.json` 里,跨作业累加。
  否则被墙钟打断后续算,每轮都拿到一个新时限,慢腿永远耗不完。
- 一条腿超时 → 杀掉,**整个 case 判死**(三条腿是一组,一条不收敛整组就没意义),
  同 case 还在跑的兄弟腿一并杀掉腾位置。
- 判死 = 写惩罚指标,CMA 把它排在末位后正常推进,不会卡住这一代。
- 日志里能看到 `[timeout] ... 判定这组乘子不收敛` 和 `[dead] ... 算太久`。

设成 0 就是不限时(旧行为)。

**断点续算是自动的**:腿完成的判据是 `_COMPLETE` 标记 + 四个非空 `*_final.csv`,
已完成的腿下次直接跳过,未完成的从 `checkpoint/` 接着算。作业被杀、被抢占、
墙钟到点都不会丢进度。

---

## 七、运行目录怎么命名:统一科学计数法

扫描值一律编成 **`<尾数>e<指数>`**(尾数归一到 `[1,10)` 去尾随零):

| 写法 | 目录 | | 写法 | 目录 |
|---|---|---|---|---|
| `0.1` / `0.10` / `.1` / `1e-1` | `ft1e-1` | | `1.0` / `1.00` / `1` | `ft1e0` |
| `0.05` | `ft5e-2` | | `1.5` | `ft1.5e0` |
| `0.125` | `ft1.25e-1` | | `10` | `ft1e1` |
| `1e-4` / `0.0001` | `ft1e-4` | | `15` | `ft1.5e1` |

双射:值 → 名字唯一,名字 → 值也唯一,**永不撞名**,小数位数随便加。

```bash
mf runid ft --key front_thick 0.05 0.125 1.0 10   # 只算名字, 不建目录
mf runid ft --decode ft1.25e-1                    # 反解: 0.125
mf migrate 'ft*'                                  # 老名字 (ft01/ft10) 迁移, 先看计划
mf migrate 'ft*' --apply                          # 真改; 数据原样保留
```

---

## 八、结构

```
代码 (只读, 一份)                        数据 ($SCRATCH/matfdm_runs/<id>/)
matfdm/                                  <id>/
├── build_p_decouple.m  基线参数           ├── config.json      唯一配置源
├── rhs_aks.m …         物理                ├── provenance.txt   commit + 配置快照
├── run_calibration_case.m 一条腿           ├── decouple/<case>/dose<d>/
├── run_root.m          数据根解析          ├── checkpoint/<case>/
├── read_run_config.m   读 config.json      ├── node-<job>-r<k>.log
└── calibration/                           └── calibration/
    ├── ctl/                                   ├── metrics/<case>.csv
    │   ├── JOB.sh            提交入口          ├── state.json
    │   ├── matfdm.sh         管理命令          ├── optimizer/  CMA pickle+历史
    │   ├── build_standalone.sh 编译            ├── logs/       每条腿 diary
    │   ├── matfdm_run.m      standalone 入口   └── DONE / STOP
    │   ├── matfdm_mcr.sh     调 standalone
    │   ├── run_generation.py 代循环编排 (MCR)
    │   ├── multi_node.sh     N 节点作业
    │   ├── node_task.sh      单节点任务
    │   ├── single_node.sh    单节点作业
    │   ├── run_generation.m  代循环 (回退, parpool)
    │   ├── lic_seat.sh       license 席位 (仅回退路线)
    │   ├── run_id.py         扫描值 <-> 运行名
    │   ├── migrate_run_ids.py 老命名迁移
    │   ├── gen_tool.py       代级助手
    │   ├── show_best.py      排名+参数
    │   ├── export_best.py    逐运行导前 N 名
    │   ├── rescore_best.py   换标尺后重算
    │   └── patch_objective.py 目标函数补丁
    ├── optimizer/     CMA-ES
    ├── vendor/        pycma
    └── docs/          本文件

数据根还有:
$SCRATCH/matfdm_runs/postprocess/   mf export 的产物
$SCRATCH/matfdm_build/CURRENT/      编译产物
```

**引擎**:`run_generation.py` 每代 fork `workers` 个 `matfdm_run leg` 进程,
各跑一条腿,互不通信。CMA-ES 全在 Python,编译不影响它。

**隔离**:`MATFDM_RUN` 指到哪数据写到哪;代码目录永远只读,多个运行/节点互不可见。

**指纹**:`params.txt` = 乘子 + 基线 + 全部关键标量,改任何物理量旧腿自动作废重算。

---

## 九、故障对照

| 现象 | 处理 |
|---|---|
| `没有编译产物` | 先在计算节点跑 `build_standalone.sh` |
| `mcc` 说 `Could not create output file` | 上次的二进制还在,`build_standalone.sh` 已会先清;手动清 `rm $SCRATCH/matfdm_build/<commit>/matfdm_run` |
| `PathAlterationNotSupported` | 编译版不许 `addpath`;新加的代码里不要调,已有的用 `if ~isdeployed` 包住 |
| 腿秒退 `rc=20` | 看 `<run>/calibration/logs/<tag>_dose<d>_error.log` |
| 节点空转"清单里没有第 k 行" | 清单行数 < 节点数, 正常 |
| 秒退"已命中且仍达标" | 真命中;想继续就收紧 `middle_max` 或删该运行的 `DONE` |
| 秒退"STOP 存在" | `mf resume <id>` |
| `future feature annotations` | 用了 /usr/bin/python3 (3.6);`module load python` |
| `CMA-ES 提议失败` | 看日志里紧跟的 python 报错;缺指标会自动 `penalize-missing` 重试 |
| `与 POPULATION 不符` | `config.json` 的 `population` 和磁盘上该代的 case 数对不上,人工确认 |
| 某腿反复失败 | 3 次后熔断,不卡整代 |
| 某腿算不完、一代迟迟不推进 | 设 `leg_timeout`（如 10800 = 3 h）。腿慢本身就是走到刚性区域的信号,超时即判该 case 不收敛并丢弃,CMA 拿到惩罚样本继续走 |
| `dose3` 的腿迟迟不返回 | 正常。辐照段**不存断点也不看墙钟预算**(源码里的设计决定:中断则整段重跑),参考耗时约 5200 s;墙钟预算只在氧化段生效。所以 `WALLTIME` 不要小到装不下一个辐照段 |
| 内存吃紧 | 单腿约 1.8 GB;`workers` × 1.8 GB 要留余量(120 腿实测峰值 215 GB / 503 GB) |
| MCR 启动慢 / Lustre 卡 | `MCR_CACHE_ROOT` 必须在节点本地 `/tmp`,`multi_node.sh` 已设好 |
| 还在占 license | 确认 `MATFDM_ENGINE` 不是 `matlab`;`mn_*.out` 里应打印 `license : 0 个席位` |
| 成分残差永远到不了 0 | 预期。Cr+Fe+Ni 口径下有 0.87/2.38/3.94 at% 的地板（模型不产 Ni）；想去掉地板就换 `COMPOSITION_BASIS=crfe` |
| 一代里没一个可行样本 | 成分不是硬约束，看的是 Cr 库存单调与端点带；放宽 `endpoint_band` 或检查库存是否倒挂 |
| 后处理绝对值可疑 | `baseline.json` 的 `build_commit` 与当前 commit 对不上 = 源码改了没重编 |
