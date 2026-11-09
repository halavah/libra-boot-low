# -*- coding: utf-8 -*-
"""field_builder 类型转换表关键路径单测"""
import sys, os
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from module.field_builder import FieldBuilder

def test_input_maps_to_string_varchar():
    d = FieldBuilder().build({'name': 'title', 'label': '标题', 'type': 'input'})
    assert d.java_type == 'String'
    assert d.mybatis_jdbc_type == 'VARCHAR'

def test_select_maps_to_el_select():
    d = FieldBuilder().build({'name': 'st', 'label': '状态', 'type': 'select',
                              'options': [{'label': '启用', 'value': '1'}]})
    assert d.vue_component == 'el-select'

def test_name_transforms():
    d = FieldBuilder().build({'name': 'create_time', 'label': '创建时间', 'type': 'datetime'})
    assert d.name_camel == 'createTime'
    assert d.name_pascal == 'CreateTime'
    assert d.column_name == 'create_time'
