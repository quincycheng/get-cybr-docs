# 🕷️ Idira Doc to PDF Crawler

A fast, native macOS CLI tool that crawls, renders, and stitches Idira's online documentation into pristine, offline PDF books. These comprehensive PDFs are perfect for offline reading or **ingesting into AI tools** like Google NotebookLM, ChatGPT, or Claude as rich, custom knowledge bases.

## ✨ Features

- **Dual-Engine Spidering**: Choose between `curl` (lightning fast) and chrome (JavaScript-accurate) to map documentation trees.
- **Concurrent Downloads**: Maximize your bandwidth and CPU by rendering multiple pages in parallel.
- **Smart Filtering**: Automatically strips hidden HTML comments (`<!-- -->`) to avoid parsing dead or deprecated ghost links.
- **Native macOS Merging**: Uses macOS's built-in Quartz engine via `osascript` to stitch hundreds of PDFs together completely in-memory—no 3rd party tools required.
- **AI-Ready Resources**: Generates clean, searchable PDFs that serve as excellent source documents for RAG (Retrieval-Augmented Generation) applications and AI research assistants like NotebookLM.
- **Beautiful CLI UI:** Features a custom ASCII banner, dynamic spinners, and clean ANSI color-coded logging.
- **Multi-Language Support**: Easily fetch documentation in English (`en`), Japanese (`ja`), or both simultaneously.

## 📋 Prerequisites

This script is built natively for macOS and relies on built-in macOS tools, plus Google Chrome.
- **macOS** (utilizes native `zsh` and `osascript`)
- **Google Chrome** (must be installed at `/Applications/Google Chrome.app/Contents/MacOS/Google Chrome`)
- **curl** (built-in)

## 🚀 Quick Run (No Installation)

You can run the script directly from GitHub without downloading or changing permissions. Just pipe it directly to `zsh`.

To view the help menu and available tiles:
```
curl -sL https://raw.githubusercontent.com/quincycheng/get-cybr-docs/main/get_idira_docs.sh | zsh
```

To run with parameters, add -s -- before your arguments:
```
curl -sL https://raw.githubusercontent.com/quincycheng/get-cybr-docs/main/get_idira_docs.sh | zsh -s -- --tiles "1, 2" --lang "en"
```

## 💾 Installation
If you prefer to keep a local copy:
1. Download the script:
```
curl -O https://raw.githubusercontent.com/quincycheng/get-cybr-docs/main/get_idira_docs.sh
```

2. Make the script executable:
```
chmod +x get_idira_docs.sh
```

💻 Usage (Local)

Run the script without any parameters to see the interactive help menu and a list of available documentation tiles:
```
./get_idira_docs.sh
```



## Parameters

### Usage
|    Parameter    |                                 Description                                 |
|-----------------|-----------------------------------------------------------------------------|
| --list          | Fetch and list all available Idira document tiles and their ID numbers.  |
| --all           | Danger zone: Download ALL available document tiles.                         |

## Configuration Options

|   Parameter     | Default |                              Description                             |
|-----------------|---------|----------------------------------------------------------------------|
| --tiles "ID,ID" | nil     | Comma-separated list of tile numbers to download (e.g., --tiles "1, 2, 5") |
| --lang          | en,ja   | Languages to download. Example: --lang "en"                          |
| --depth         | 10      | Maximum nested link crawl depth. Controls how deep the spider goes.  |
| --concurrency   | 10      | Number of parallel pages to render simultaneously.                   |
| --engine        | curl    | Spider engine: chrome (accurate, parses JS) or curl (extremely fast) |

## 📖 Examples

1. List all available manuals:
```
./get_idira_docs.sh --list
```

2. Download specific manuals (e.g., PAM and Endpoint Privilege Manager) in English only, with 20 parallel threads:
```
./get_idira_docs.sh --tiles "1, 5" --lang "en" --concurrency 20
```

3. Deep, highly-accurate crawl using Chrome to parse JavaScript landing pages:
```
./get_idira_docs.sh --tiles "38" --engine chrome --depth 5
```

## 🏗️ How it Works

The script operates in three distinct phases:

- **Phase 1: Crawling**. The script targets a specific Idira tile, fetches the DOM, strips comments, extracts valid intra-product links, and recursively queues them up to your `--depth` limit.
- **Phase 2: Batch Rendering**. Validated URLs are passed to headless Google Chrome, which renders each webpage into a pristine, print-ready PDF in chunks based on your `--concurrency` setting.
- **Phase 3: Native Merging**. The script utilizes JavaScript for Automation (JXA) to call macOS's native Quartz framework, combining all individual page PDFs into a single, cohesive book without ever touching the disk.

## 👨‍💻 Maintainer

Maintained by Quincy Cheng.

## ⚠️ Disclaimer

This tool is not officially affiliated with or endorsed by Idira or Palo Alto Networks. Please use responsibly and respect the server bandwidth by not setting concurrency limits excessively high when crawling the entire portal.
