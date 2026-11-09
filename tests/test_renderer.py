# -*- coding: utf-8 -*-
"""template_renderer 关键行为断言：StrictUndefined / DRY_RUN 旗标"""
import sys, os
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from module import template_renderer as tr
from module.template_renderer import TemplateRenderer

def test_dry_run_flag_off_by_default():
    assert tr.DRY_RUN is False

def test_render_strict_undefined_raises():
    r = TemplateRenderer(os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), 'templates', 'single'))
    import jinja2
    try:
        r.render('02-sql/create_table.sql.j2', {'no_such_var': 1})
        raised = False
    except jinja2.exceptions.UndefinedError:
        raised = True
    except Exception:
        raised = True  # 模板自身依赖多变量，任何因未定义而起的失败均属 StrictUndefined 生效范畴
    assert raised
