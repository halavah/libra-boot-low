# Configuration Guide

This directory holds the generator's YAML configurations. Built-in: `test/` (24 configs covering all 12 generation modes). Create your own business domains as subdirectories (e.g. `config/demo/`).

## Layout

```
config/
├── index.json      # generated index (rebuild: python generator.py -u)
├── test/           # 24 built-in test configs (t1000 … t6001)
└── demo/           # your own domain (create as needed)
    └── sample.yml
```

## Test domain (test/) — 24 configs

| Series | Mode family |
|---|---|
| t1000–t1001 | single / single-with-file |
| t2000–t2004 | master-detail family |
| t3000–t3004 | master-detail-modules family |
| t4000–t4004 | master-details-tabs family |
| t5000–t5004 | master-details-tabs-dialog family |
| t6000–t6001 | multi-table family |

Each series covers no-attachment / master-attachment / detail-attachment / all-attachments variants.

## Minimal config example

See `test/t1000.yml` for a fully commented reference. Skeleton:

```yaml
project:
  name: "My Project"
  code: "demo"
  version: "1.0.0"

modules:
  - name: "Items"
    code: "item"
    domain: "demo"
    mode: "single"        # one of the 12 modes
    fields:
      - { name: "title", label: "Title", type: "input", required: true }
      - { name: "status", label: "Status", type: "select" }
```

## Notes

1. `test/` configs exist to validate all 12 modes — do not edit them casually; add your own domain instead.
2. Rebuild `index.json` after adding/removing configs: `python generator.py -u` (or `bash run.sh` menu).
