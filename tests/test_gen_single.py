# -*- coding: utf-8 -*-
"""gen_single 产物结构断言：六段目录与关键文件"""
import sys, os, tempfile, shutil
from pathlib import Path
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from module.config_loader import ConfigLoader
from module.field_builder import FieldBuilder
from module.template_renderer import TemplateRenderer
from module.gen_single import generate as gen_single

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

def test_gen_single_produces_six_segments():
    tmp = tempfile.mkdtemp(prefix='lbl-gen-')
    try:
        cl = ConfigLoader(os.path.join(ROOT, 'config/test/t1000.yml')); cl.load()
        m = cl.get_modules()[0]
        n = gen_single(cl, FieldBuilder(), TemplateRenderer,
                       Path(os.path.join(ROOT, 'templates')), Path(tmp),
                       cl.config.get('project', {}), m)
        assert n > 0
        out = os.path.join(tmp, 'test', 't1000')
        for seg in ('00-inbox', '01-design', '02-sql', '03-http', '04-server', '05-web'):
            assert os.path.isdir(os.path.join(out, seg)), f'缺段: {seg}'
        assert any(f.endswith('.sql') for f in os.listdir(os.path.join(out, '02-sql')))
        assert any(f.endswith('.http') for f in os.listdir(os.path.join(out, '03-http')))
    finally:
        shutil.rmtree(tmp, ignore_errors=True)
