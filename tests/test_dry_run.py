# -*- coding: utf-8 -*-
"""DRY_RUN 零落盘行为单测（子进程级）"""
import subprocess, sys, os, tempfile, shutil

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

def test_dry_run_writes_nothing():
    tmp = tempfile.mkdtemp(prefix='lbl-dryrun-')
    pre_output_exists = os.path.exists(os.path.join(ROOT, 'output'))  # 预快照：环境残留不算回归
    try:
        out = os.path.join(tmp, 'out')
        r = subprocess.run([sys.executable, 'generator.py', 'config/test/t1000.yml', out, '--dry-run'],
                           cwd=ROOT, capture_output=True, text=True)
        assert r.returncode == 0, r.stderr[-500:]
        assert not os.path.exists(out), 'DRY-RUN 不应创建输出目录'
        assert pre_output_exists or not os.path.exists(os.path.join(ROOT, 'output')), 'DRY-RUN 不应新建报告目录'
    finally:
        shutil.rmtree(tmp, ignore_errors=True)
