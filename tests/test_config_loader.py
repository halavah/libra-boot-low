# -*- coding: utf-8 -*-
"""config_loader 关键路径单测：模式表/加载/校验/域映射"""
import sys, os
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from module.config_loader import ConfigLoader

def test_valid_modes_is_13():
    assert len(ConfigLoader.VALID_MODES) == 13  # 12 业务拓扑 + cloud-service（微服务独立服务·L 批新增）

def test_load_and_validate_t1000():
    cl = ConfigLoader('config/test/t1000.yml')
    cfg = cl.load()
    assert cfg is not None
    ok, errors = cl.validate()
    assert ok, errors

def test_get_modules_enriched():
    cl = ConfigLoader('config/test/t1000.yml'); cl.load()
    m = cl.get_modules()[0]
    assert m['code'] == 't1000'
    assert m['mode'] == 'single'
    assert m['domain'] == 'test'

def test_domain_chinese_map_generic():
    assert ConfigLoader.DOMAIN_CHINESE_MAP == {'demo': '示例业务域', 'test': '测试验证域'}

def test_invalid_mode_fails_validation():
    cl = ConfigLoader('config/test/t1000.yml'); cl.load()
    cl.config['modules'][0]['mode'] = 'not-a-mode'
    ok, _ = cl.validate()
    assert not ok
