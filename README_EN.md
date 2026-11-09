<div align="center">

# 🚀 Libra Boot Low

**Low-code generator based on YAML config + Jinja2 templates — one command to a full Spring Boot + Vue3 skeleton**

[![PyPI](https://img.shields.io/pypi/v/libra-boot-low)](https://pypi.org/project/libra-boot-low/)
[![PyPI downloads](https://img.shields.io/pypi/dm/libra-boot-low)](https://pypi.org/project/libra-boot-low/)
[![Python](https://img.shields.io/badge/Python-3.9+-blue.svg)](https://www.python.org/)
[![License](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)
[![Spring Boot](https://img.shields.io/badge/generates-Spring%20Boot-6DB33F.svg)](https://spring.io/projects/spring-boot)
[![Vue3](https://img.shields.io/badge/generates-Vue3-42b883.svg)](https://vuejs.org/)

**English** | [简体中文](README.md)

</div>

> **This README follows the open-source documentation spec**: uniform structure and badges, badges point only to publicly reachable resources, version info points to the dynamic release-channel page.


---

## 📖 Table of Contents

- [Quick Start](#-quick-start)
- [Generation Pipeline](#-generation-pipeline)
- [12 Generation Modes](#-12-generation-modes)
- [Installation](#-installation)
- [Tests](#-tests)
- [CLI Options](#-cli-options)
- [Contributing](#-contributing)
- [License](#-license)
- [Contact](#-contact)
- [Star History](#-star-history)

---

## 🚀 Quick Start

```bash
# Install dependencies
pip install -r requirements.txt

# Generate with example config
python3 generator.py config/test/t1000.yml

# Or use the interactive menu
bash run.sh

# Generate all modules
bash run.sh --all
```

## 🔄 Generation Pipeline

```
YAML Config → generator.py → module/gen_*.py → templates/{mode}/ → out/{domain}/{code}/
```

## 🧩 12 Generation Modes

| Mode | Description |
|------|-------------|
| `single` | Single-table CRUD |
| `single-with-file` | Single-table + file upload |
| `multi-table` | Multi-table with relations |
| `multi-table-with-file` | Multi-table + file upload |
| `master-detail` | Master-detail (one-to-many) |
| `master-detail-with-file` | Master-detail + file upload |
| `master-detail-modules` | Master-detail (modularized sub-modules) |
| `master-detail-modules-with-file` | Modularized master-detail + file upload |
| `master-details-tabs` | Master with multiple detail tabs |
| `master-details-tabs-with-file` | Detail tabs + file upload |
| `master-details-tabs-dialog` | Detail tabs with dialog editing |
| `master-details-tabs-dialog-with-file` | Detail tabs dialog + file upload |

## 📦 Installation

| Channel | Command | Status |
|---|---|---|
| PyPI | `pip install libra-boot-low` | ✅ Live |
| GitHub Release wheel (internal) | `pip install https://github.com/halavah/libra-boot-low/releases/latest/download/libra_boot_low-1.1.2-py3-none-any.whl` | ✅ Live |
| Direct from git (internal) | `pip install git+https://github.com/halavah/libra-boot-low.git` | ✅ Live |
| Run from source | `pip install -r requirements.txt` then `python3 generator.py` | ✅ Live |

## 🧪 Tests

```bash
pip install pytest
python -m pytest tests/ -q   # 12 cases: config loading / type mapping / DRY_RUN zero-write / renderer / single-mode output structure
```

## ⌨️ CLI Options

| Option | Description |
|--------|-------------|
| `--version` | Show version |
| `--list-modes` | List all supported modes |
| `--dry-run` | Preview files without writing |
| `--module <code>` | Generate a specific module only |
| `--mode <mode>` | Override mode from YAML |
| `--validate` | Validate config without generating |
| `--list` | List modules in a config |
| `--update-index` | Rebuild config/index.json |

The `run.sh` / `run.ps1` launchers additionally provide an interactive menu, `--all` (batch generate everything) and `--domain <name>` filtering.

## 🤝 Contributing

Issues and Pull Requests are welcome!

```bash
# 1. Fork this repository
# 2. Create a feature branch
git checkout -b feature/your-feature
# 3. Run tests before submitting
python -m pytest tests/ -q
# 4. Push and open a PR
git push origin feature/your-feature
```

**Contribution guidelines**:
- New features must include test cases (`tests/` directory)
- Template changes must pass full dry-run regression (24 configs, zero disk writes)
- Commit messages should describe changes in Chinese

## 📄 License

MIT License — See [LICENSE](LICENSE) file for details.

### License Summary

MIT is one of the most permissive open-source licenses:

- ✅ **Permitted**: Commercial use, modification, distribution, private use, patent use
- ⚠️ **Only requirement**: Preserve copyright and license notices
- ❌ **Not provided**: Author warranty, liability

**Why MIT?**

This is a tool-type project. MIT was chosen for:
- **Zero barrier**: Enterprises can adopt without copyleft concerns
- **Output independence**: Generated code is NOT bound by this project's license
- **Community friendly**: Encourages forks and derivative work

## 📮 Contact

**Maintainer**: Halavah
**GitHub**: [@halavah](https://github.com/halavah)

**Links**:
- Repository: [GitHub](https://github.com/halavah/libra-boot-low)
- Issues: [Issue Tracker](https://github.com/halavah/libra-boot-low/issues)
- Releases: [PyPI](https://pypi.org/project/libra-boot-low/)

## ⭐ Star History

If this project helps you, please give us a ⭐ Star! Your support is our greatest motivation!

[![Star History Chart](https://api.star-history.com/svg?repos=halavah/libra-boot-low&type=Date)](https://star-history.com/#halavah/libra-boot-low&Date)

---

**Made with ❤️**

If this project helps you, please consider giving us a ⭐ Star

[⬆ Back to Top](#-libra-boot-low)
