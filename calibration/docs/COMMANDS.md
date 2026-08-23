# matfdm 标定 — 操作手册

## 一、提交作业(只需要这一件事)

**所有设置都在 `calibration/ctl/JOB.sh` 顶部的设置区里,改完直接跑:**

```bash
cd $SCRATCH/projects/matfdm
vi calibration/ctl/JOB.sh        # 改设置区
bash calibration/ctl/JOB.sh      # 建运行目录 + 生成清单 + 提交作业链
```

它会打印每个运行、清单路径、以及提交出去的作业号,最后给出看进度的命令。

### JOB.sh 设置区

```bash
ACCOUNT=m5181                 # SLURM 账号
WALLTIME=18:00:00             # 每个作业的墙钟
NJOBS=4                       # 排几轮接力 (afterany 链, 断点续算)
QOS=regular                   # regular / debug / preempt

CODE=$SCRATCH/projects/matfdm # 代码目录 (只读)
RUNS=$SCRATCH/matfdm_runs     # 数据根

SWEEP_KEY=front_thick         # 要扫的字段
SWEEP_VALUES="0.05 0.1 ... 1.5"   # 每个值一个运行, 一个运行占一个节点
PREFIX=ft                     # 目录名前缀 -> ft1e-1, ft5e-1, ft1e0 ...

POPULATION=40                 # 每代 case 数
WORKERS=120                   # parpool worker 数 (= POPULATION × 剂量数)
DOSES="[0, 0.5, 3]"
TARGETS="[40, 60, 100]"
MIDDLE_MAX=70                 # 0.5 dpa 软带上限 nm
ENDPOINT_BAND=5               # 端点硬约束 nm
ENDPOINT_TOL=3                # 成功判据端点容差 nm
MAX_ATTEMPTS=3
KEEP_TRAJ=false
SEED=20260804

OVERRIDES='{"eff": 0.2}'      # 物理参数覆盖, 不改源码

LIC_SEATS=2                   # 同时允许几个节点"试签出" MATLAB license (0=不设闸)
LIC_BACKOFF=30                # 抢不到的退避基数 s (指数增长 + 抖动)
LIC_BACKOFF_MAX=600           # 退避上限 s
LIC_HOLD=420                  # 入闸令牌最长持有 s (不是放弃时限)
```

**节点数 = `SWEEP_VALUES` 的个数**,`JOB.sh` 自动算,不用手填 `-N`。
30 个值 → 每个作业 30 节点;`NJOBS=4` → 4 × 18 h = 最多 72 h 连续算。

### 运行目录怎么命名:统一科学计数法

扫描值一律编成 **`<尾数>e<指数>`**(尾数归一到 `[1,10)` 去尾随零,指数是带符号整数):

| 写法 | 规范值 | 目录 |
|---|---|---|
| `0.1` / `0.10` / `.1` / `1e-1` | `1e-1` | `ft1e-1` |
| `0.2` | `2e-1` | `ft2e-1` |
| `0.05` | `5e-2` | `ft5e-2` |
| `0.125` | `1.25e-1` | `ft1.25e-1` |
| `1.0` / `1.00` / `1` | `1e0` | `ft1e0` |
| `1.5` | `1.5e0` | `ft1.5e0` |
| `10` | `1e1` | `ft1e1` |
| `15` | `1.5e1` | `ft1.5e1` |
| `1e-4` / `0.0001` | `1e-4` | `ft1e-4` |

这是个**双射**:值 → 名字唯一,名字 → 值也唯一(名字去掉前缀就是一个合法的十进制
字面量)。所以**永远不会撞名**,小数位数想加多少加多少,同一个值不管怎么写都落进同
一个目录。

```bash
mf runid ft --key front_thick 0.05 0.125 1.0 10   # 只算名字, 不建目录
# ft5e-2 5e-2 / ft1.25e-1 1.25e-1 / ft1e0 1e0 / ft1e1 1e1
mf runid ft --decode ft1.25e-1                    # 反解: 0.125
```

老做法是直接删掉小数点(`tr -d '.'`),三个坑,已全部作废:

- `1.0` 和 `10` 都得 `ft10`、`1.5` 和 `15` 都得 `ft15` —— 两条链写进同一个目录,
  CMA 状态和 metrics 混在一起,两条都废,而且全程没有任何报错;
- `0.1` 写成 `0.10` 会另开一个 `ft010`,把已经算了几百次评估的 `ft01` 孤立掉;
- 位数一混,目录名的字典序和数值大小完全对不上。

**已有目录已经迁移过了**(`ft01`→`ft1e-1` … `ft10`→`ft1e0`,数据原样保留)。
以后若还有老名字的目录:

```bash
mf migrate 'ft*'              # 先看计划 (dry-run)
mf migrate 'ft*' --apply      # 真改: 目录改名 + config.json/provenance 的 run_id 跟着改
                              #       + 清单重写 + 老的后处理 txt 作废
```

结果、断点、CMA 状态里都不含运行名或运行目录路径,所以改名不影响续算。

> 整数扫描(比如 `seed`)也走同一套规则,`101` → `seed1.01e2`。统一是有代价的,
> 但换来的是永不撞名;想要好看的名字就自己 `mf new <id> seed=101` 显式指定。

### 常见几种扫描

```bash
# 前沿判据阈值
SWEEP_KEY=front_thick ; SWEEP_VALUES="0.25 0.5 0.75 1.0 1.5 2.0" ; PREFIX=ft

# 级联效率 (物理参数走 overrides.)
SWEEP_KEY=overrides.eff ; SWEEP_VALUES="0.05 0.1 0.15 0.2 0.25 0.3" ; PREFIX=eff

# Ni 排出速率
SWEEP_KEY=overrides.Dgb ; SWEEP_VALUES="1e-4 5e-4 1e-3 5e-3" ; PREFIX=dgb

# 0.5 dpa 软带上限
SWEEP_KEY=middle_max ; SWEEP_VALUES="60 65 70 75" ; PREFIX=mm

# 多条独立 CMA 链 (同配置不同种子)
SWEEP_KEY=seed ; SWEEP_VALUES="101 202 303 404 505" ; PREFIX=seed
```

### 单个运行(调试用)

```bash
alias mf='bash $SCRATCH/projects/matfdm/calibration/ctl/matfdm.sh'
mf new test front_thick=0.5 population=40 overrides.eff=0.2
mf submit test 2                 # 2 个单节点接力作业
```

### 交互节点验证(不占正式机时)

```bash
salloc -N 5 -q interactive -C cpu -t 01:00:00 -A m5181
export MATFDM_CODE=$SCRATCH/projects/matfdm
export MATFDM_MANIFEST=$SCRATCH/matfdm_runs/runs_ft.txt
bash $MATFDM_CODE/calibration/ctl/multi_node.sh
```

每个节点日志里出现 `[gen 01] 40 cases x 3 dose = 120 legs` 就是通了。

### MATLAB license 席位(自动,一般不用管)

NERSC 的 MATLAB / Parallel Computing Toolbox license 是**全校共享**的,10 个节点
同时起 MATLAB 抢不到很正常。抢不到时节点**不会退出**,而是原地退避重试到墙钟为止:

| 层 | 在哪 | 干什么 |
|---|---|---|
| 入闸令牌 | `lic_seat.sh` | 同一时刻最多 `LIC_SEATS` 个节点在试签出,避免一起冲服务器 |
| 放闸 | `run_generation.m` → `node_task.sh` | `parcluster` 一成功就写 READY 标记,令牌立刻还给下一个排队节点 |
| 节点侧重试 | `node_task.sh` | MATLAB 基础 license 没抢到 → 退避 `LIC_BACKOFF`→`LIC_BACKOFF_MAX` s 重试 |
| MATLAB 侧重试 | `run_generation.m` | PCT 没抢到 → 原地重试,**不丢**已经到手的基础席位 |
| 令牌回收 | `lic_seat.sh` | 节点被 SIGKILL 留下的令牌,`LIC_HOLD` 秒后自动回收 |

**什么时候放弃:只看墙钟。** 节点一路重试到作业结束前 5 分钟(`MATFDM_LIC_GIVEUP`,
默认 300 s),退避封顶 600 s,所以 8 h 的作业里一个节点大约重试 50–90 次。
`LIC_SEATS` / `LIC_BACKOFF` / `LIC_HOLD` **都不是放弃时限** —— `LIC_HOLD` 只管入闸
令牌:超时就认定持有者已死、把令牌收回去,被收的那个节点的 MATLAB 照常跑。

退避带随机抖动(equal jitter),否则 N 个节点会永远在同一秒一起重试,等于没退避。

```bash
grep -c '^--- 第 ' $SCRATCH/matfdm_runs/ft5e-1/node-*.log     # 这个节点抢了几次
grep 'license 到手' $SCRATCH/matfdm_runs/ft*/node-*.log      # 谁抢到了, 花了多久
ls $SCRATCH/matfdm_runs/.lic_seats                          # 当前谁占着入闸令牌
```

**为什么必须这么做**:老版本抢不到就 `exit 1`,作业 2 分钟"跑完",`afterany`
接力链被瞬间烧光 —— 2026-08-23 那次 13 个作业 20 分钟全部空转结束,一代都没算。

---

## 二、看进度

```bash
alias mf='bash $SCRATCH/projects/matfdm/calibration/ctl/matfdm.sh'
```

| 目的 | 命令 |
|---|---|
| 全部运行总览 | `mf status` |
| 某运行的 CMA 状态 | `mf status ft5e-1` |
| 前十名 + 参数绝对值 | `mf best ft5e-1 10` |
| **每个运行各导一份前十名 txt** | `mf export 'ft*' 10` |
| 某节点抢了几次 license | `grep -c '^--- 第 ' $SCRATCH/matfdm_runs/ft5e-1/node-*.log` |
| 队列 | `squeue --me -o "%.10i %.12j %.6D %.8T %.9M %.20R"` |
| 多节点作业总日志 | `tail -f $SCRATCH/matfdm_runs/mn_ft-*.out` |
| 某节点日志 | `tail -f $SCRATCH/matfdm_runs/ft5e-1/node-*.log` |
| 某条腿跑到第几窗 | `tail -3 $SCRATCH/matfdm_runs/ft5e-1/calibration/logs/b12_c07_cma_dose3.log` |
| 某 case 三行指标 | `column -s, -t $SCRATCH/matfdm_runs/ft5e-1/calibration/metrics/b12_c07_cma.csv` |
| 排名(现算, 不读快照) | `MATFDM_RUN=$SCRATCH/matfdm_runs/ft5e-1 python3 $MATFDM_CODE/calibration/ctl/gen_tool.py rank --top 20` |
| 某一代逐 case | `MATFDM_RUN=… python3 …/gen_tool.py report 12` |
| 节点内存/进程 | `ssh <node> 'pgrep -c -u $USER -f MATLAB; free -g\|sed -n 2p'` (应 121 进程) |

`fitness_history.csv` 和 `cma_generation.json` 是**上一次 propose 的快照**;改过目标函数要用 `rank` / `best` 现算,或等下一代刷新。

**时间参考**:pool 启动 5–6 min,单腿约 52 min,一代 1–1.5 h,18 h 作业约 12–16 代。

---

## 三、后处理:每个 ft 的前十名导成 txt

```bash
mf export                       # 全部 ft*, 前十名 -> $SCRATCH/matfdm_runs/postprocess/ft1e-1.txt ...
mf export 'ft*' 20              # 前二十名
mf export 'eff*' 10 ~/out       # 换扫描前缀 / 换输出目录
```

底层就是 `export_best.py`,想直接调也行:

```bash
module load python
MATFDM_RUNS=$SCRATCH/matfdm_runs \
  python3 $MATFDM_CODE/calibration/ctl/export_best.py --pattern 'ft*' --top 10 --csv
```

| 参数 | 默认 | 说明 |
|---|---|---|
| `--pattern` | `ft*` | 运行目录通配 |
| `--top` | 10 | 每个运行取前几名 |
| `--out` | `<数据根>/postprocess` | 输出目录 |
| `--csv` | 关 | 顺带导一份同名 `.csv` |

每个运行一个文件,**文件名 = 运行目录名**(`ft1e-1.txt`、`ft2e-1.txt`…)。正文格式与
`mf best` / `show_best.py` 完全一致 —— 脚本是逐个运行去调 `show_best.py`,不是
把排版逻辑另抄一遍,所以将来改 `show_best.py` 的输出这里自动跟着变。文件头另加
一段运行信息(目录、导出时间、已评估数、config、命中标记)。

判据(`population` / `middle_max` / `endpoint_band` / `seed`)取**该运行自己的
`config.json`**,不是全局默认值 —— 扫 `middle_max` 这类字段时各运行标尺不同,
用错标尺排出来的名次是假的。

终端同时打印一张总表,一眼看出哪个 `front_thick` 最有戏:

```
扫描   : front_thick

运行        front_thick     评估     可行      最佳 fitness  文件
ft1e-1           0.1    560  0/560    1014165.3390  ft1e-1.txt
ft4e-1           0.4    800  0/800    1077050.3453  ft4e-1.txt
ft8e-1           0.8      0      -               -  ft8e-1.txt  <- 一代都没跑完
```

**排序按扫描值的数值,不是目录名的字典序** —— 位数一混字典序就乱:
字典序里 `ft1e0`(=1)排在 `ft2e-1`(=0.2)前面,和 `front_thick` 的大小顺序对不上。
扫描字段自动认出来(一组运行里取值不全相同的那个数值字段);认不出来就退回按名字
自然排序。

---

## 四、停 / 续 / 清

```bash
mf stop ft5e-1                          # 该运行的节点空转退出
mf resume ft5e-1
mf clean ft5e-1                         # 清数据, 保留 config.json
touch $SCRATCH/matfdm_runs/ft*/calibration/STOP     # 全停
squeue --me -h -o "%i %j" | awk '$2 ~ /^mn_ft/ {print $1}' | xargs -r scancel
```

---

## 五、改配置

改 `config.json` **不需要动代码**,下一个作业自动生效;涉及物理的改动会通过参数指纹让旧腿自动作废重算。

```bash
vi $SCRATCH/matfdm_runs/ft5e-1/config.json
mf new ft5e-1 front_thick=0.75          # 或增量改 (幂等, 保留其他字段)
```

改目标函数(全局):

```bash
python3 $MATFDM_CODE/calibration/ctl/patch_objective.py            # 幂等
MATFDM_RUN=$SCRATCH/matfdm_runs/ft5e-1 CALIB_POPULATION=40 \
  python3 $MATFDM_CODE/calibration/ctl/rescore_best.py             # 每个运行各跑一次
```

**时机**:改 `cma_state.pkl` 的操作(rescore/patch)要在两次 propose 之间做——看到 `[gen NN] … legs` 之后最安全,不用停作业。

### config.json 字段

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
| `seed` | 20260804 | CMA 种子 (多链要给不同值) |
| `overrides` | `{}` | 覆盖 `p` 的任意字段: `eff`、`Dgb`、`Ks`、`rOM`… |

---

## 六、结构

```
代码 (只读, 一份)                        数据 ($SCRATCH/matfdm_runs/<id>/)
matfdm/                                  <id>/
├── build_p_decouple.m  基线参数           ├── config.json      唯一配置源
├── rhs_aks.m …         物理                ├── provenance.txt   commit + 配置快照
├── run_root.m          数据根解析          ├── decouple/<case>/dose<d>/
├── read_run_config.m   读 config.json      ├── checkpoint/<case>/
└── calibration/                           ├── node-<job>-r<k>.log
    ├── ctl/                                └── calibration/
    │   ├── JOB.sh          提交入口            ├── metrics/<case>.csv
    │   ├── matfdm.sh       管理命令            ├── state.json
    │   ├── multi_node.sh   N 节点作业          ├── optimizer/  CMA pickle+历史
    │   ├── node_task.sh    单节点任务          ├── logs/       每条腿 diary
    │   ├── single_node.sh  单节点作业          └── DONE / STOP
    │   ├── run_generation.m   常驻驱动
    │   ├── run_leg_worker.m   腿包装
    │   ├── gen_tool.py        代级助手
    │   ├── show_best.py       排名+参数
    │   ├── export_best.py     逐运行导前 N 名 txt
    │   ├── run_id.py          扫描值 <-> 运行名 (科学计数法)
    │   ├── migrate_run_ids.py 老命名目录一次性迁移
    │   ├── lic_seat.sh        license 席位抢占
    │   ├── rescore_best.py    换标尺后重算
    │   └── patch_objective.py 目标函数补丁
    ├── optimizer/      CMA-ES
    ├── vendor/         pycma
    └── docs/           本文件

数据根还有两个跨运行的东西:
$SCRATCH/matfdm_runs/
├── .lic_seats/         license 入闸令牌池 (跨节点共享, 自动清理)
└── postprocess/        mf export 导出的 ft1e-1.txt / ft2e-1.txt / ...
```

**隔离**:`MATFDM_RUN` 指到哪数据写到哪;代码目录永远只读,多个运行/节点互不可见。
**配置**:`config.json` 是唯一真相源,`overrides` 在 `build_p_decouple` 之后覆盖到 `p`。
**指纹**:`params.txt` = 乘子 + 基线 + 全部关键标量,改任何物理量旧腿自动作废重算。
**容错**:腿有 checkpoint(原子写);`_COMPLETE` 标记防半截结果;单节点崩不影响其他节点;CMA 状态丢了能从 metrics 重放历史。

---

## 七、故障对照

| 现象 | 处理 |
|---|---|
| 节点空转"清单里没有第 k 行" | 清单行数 < 节点数, 正常;`JOB.sh` 会自动按行数定 `-N` |
| 秒退"已命中且仍达标" | 真命中;想继续就收紧 `middle_max` 或删该运行的 `DONE` |
| 秒退"STOP 存在" | `mf resume <id>` |
| `future feature annotations` | 用了 /usr/bin/python3 (3.6);`module load python` |
| `CMA-ES 提议失败` | 看日志里紧跟的 python 报错;缺指标会自动 `penalize-missing` 重试 |
| parpool 停住 | 120 worker 起来要 5–6 min;超 10 min 查 `pgrep -c -u $USER -f MATLAB` 是否在涨 |
| `Maximum number of users for MATLAB reached` | 正常,全校共享 license。节点会自动退避重试,**不会**再秒退;日志里看 `--- license 没抢到 (第 N 次)` |
| 作业几分钟就"跑完"、接力链被烧光 | 老版本的行为。确认 `node_task.sh` 里有 `lic_run_matlab`,且 `mn_*.out` 里打印了 `deadline:` 与 `license :` 两行 |
| 全程一代没跑完(评估 0) | 该节点整个作业都没抢到席位。调小 `LIC_SEATS`、调大 `WALLTIME`,或错峰提交 |
| 两个扫描值跑进同一个目录 | 老命名规则的锅。科学计数法是双射,不可能再撞;`mf runid <前缀> --key <字段> <值...>` 可先看一眼名字 |
| 还有 `ft01` 这种老名字的目录 | `mf migrate 'ft*'` 看计划,`--apply` 执行;数据原样保留 |
| 目录名看不出对应哪个值 | `mf runid <前缀> --decode <目录名>` 反解 |
| `mf best` 说"没有可评分的样本" | 该运行还没有 `state.json`(一代都没完);有 `state.json` 还这样就是 `CALIB_REPO_DIR` 没指到运行目录 |
| 某腿反复失败 | 3 次后熔断,不卡整代;错误在 `<run>/calibration/logs/<tag>_dose<d>_error.log` |
| 内存吃紧 | 单腿约 1.8 GB;`workers` × 1.8 GB 必须 < 400 GB |