# FileProcessor  
## Delivery 2 – Parallel File Processing 


## 1) Overview

**FileProcessor** is a file-processing system written in **Elixir** that:

- Receives one or more **inputs** (directories and/or files).
- Discovers and filters supported files (**CSV, JSON, LOG**).
- Reads file contents into memory.
- Executes **type-specific parsers** and computes **metrics**.
- Generates a **unified plain-text report**.
- With **Delivery 2**, processes files **in parallel** using workers (processes) and shows **real-time progress**.

---

## 2) Project Objective

Process files in different formats (**CSV, JSON, and LOG**) by extracting useful metrics and generating a human-readable report, with emphasis on:

- Input validation
- Explicit error handling (tuples and structures)
- Reproducible results
- Modular and extensible design
- **Concurrency** and performance improvement (Delivery 2)

---

## 3) Supported Formats

| Format | Extension | Description |
|--------|-----------|-------------|
| CSV    | `.csv`     | Sales data |
| JSON   | `.json`    | Users and sessions |
| LOG    | `.log`     | System logs |

Any other extension is explicitly rejected during **discovery**.

---

## 4) What’s new in Delivery 2

### 4.1 Parallel mode as the primary mode

- **`FileProcessor.run/1` and `FileProcessor.run/2` default to `"parallel"` mode.**
- `"sequential"` is preserved as an alternative for comparison and fallback.

### 4.2 Workers and coordinator

- One **worker (process)** is created per discovered file.
- The **coordinator** process (the process calling `run/3`) gathers results via `receive`.
- **Monitoring** (`Process.monitor/1`) is used to detect worker **crashes** and report them without stopping the entire execution.

### 4.3 Real-time progress

As results arrive, a progress line is printed, for example:

```text
[parallel] 3/6 processed: ventas_enero.csv (ok)
```

The displayed `status` depends on validations and parsing:

- `:ok` → processed with no errors
- `:partial` → processed with partial errors (e.g., invalid rows/lines)
- `:failed` → parsing failed or the worker crashed

### 4.4 Benchmark (sequential vs parallel)

A utility function is included to compare runtimes:

- `FileProcessor.benchmark/1` generates two reports:
  - `benchmark_sequential.txt`
  - `benchmark_parallel.txt`

It also prints results and an improvement factor in the console.

---

## 5) Processing Flow

### 5.1 Input reception

The system accepts:

- A **directory**
- A **file**
- A **list** of directories and/or files

### 5.2 Discovery and validation (FileReceiver)

- If the input is a directory: list files and filter by supported extensions.
- If the input is a file: validate extension.
- Duplicates are removed using `MapSet`.
- Discovery errors are **accumulated**, they do not stop execution.

### 5.3 Reading

- File contents are read into memory (`File.read/1`).
- Read errors are also accumulated.
- If there are **no valid files** to process, the function returns `{:error, errors}`.

### 5.4 Type-specific processing

Each worker delegates to the same base logic:

- CSV → `FileProcessor.Parsers.CSVParser` + `FileProcessor.Metrics.CSVMetrics`
- JSON → `FileProcessor.Parsers.JSONParser` + `FileProcessor.Metrics.JSONMetrics`
- LOG → `FileProcessor.Parsers.LogParser` + `FileProcessor.Metrics.LogMetrics`

### 5.5 Consolidation + report

- Totals are consolidated per type (CSV/JSON/LOG).
- A unified plain-text report is generated via `FileProcessor.ReportGenerator`.

---

## 6) Extracted Metrics

### 6.1 CSV 

- Total net sales
- Unique products
- Top-selling product
- Highest-revenue category
- Average discount
- Date range

### 6.2 JSON 

- Total users
- Active vs inactive users
- Average session duration
- Total pages visited
- Top 5 actions
- Peak activity hour

### 6.3 LOG 

- Total entries
- Distribution by level
- Distribution by hour
- Most frequent errors (top 5)
- Component with the most critical errors
- Time between critical errors
- Recurrent error patterns

---

## 7) Error Handling

Errors are handled explicitly through tuples and structures. Covered cases include:

- Non-existent path (file/directory)
- Directory with no supported files
- Unsupported format
- File read errors
- Parsing errors (CSV/JSON/LOG)
- Partial errors (e.g., invalid rows/lines)
- Worker crash (parallel mode only)

### Important (fail-fast on writing)

Report writing uses `File.write!/2` in `ReportGenerator.write!/2`.  
If writing fails, the process will fail immediately (intentional *fail-fast* behavior).

---

## 8) Public API

### 8.1 Execution (primary)

```elixir
FileProcessor.run/1
FileProcessor.run/2
FileProcessor.run/3
```

- `run/1` → uses `reporte_final.txt` and `"parallel"` mode.
- `run/2` → allows specifying the report name/path, `"parallel"` mode.
- `run/3` → allows choosing `"parallel"` or `"sequential"`.

### 8.2 Benchmark

```elixir
FileProcessor.benchmark/1
```

---

## 9) Usage Examples

> Note: These paths are examples. Adjust to your local structure.

### 9.1 Process a directory (parallel by default)

```elixir
FileProcessor.run("data")
# => {:ok, "/absolute/path/reporte_final.txt"}
```

### 9.2 Process a single file

```elixir
FileProcessor.run("data/sistema.log")
```

### 9.3 Process multiple inputs

```elixir
FileProcessor.run([
  "data/sistema.log",
  "data/usuarios.json",
  "data"
])
```

### 9.4 Custom report name

```elixir
FileProcessor.run("data", "output/delivery2_report.txt")
```

### 9.5 Run sequential mode (fallback)

```elixir
FileProcessor.run("data", "output/sequential_report.txt", "sequential")
```

### 9.6 Benchmark

```elixir
FileProcessor.benchmark("data")
```

---

## 10) Project Structure

```bash
file_processor/
├── lib/
│   ├── file_processor.ex
│   ├── file_receiver.ex
│   ├── report_generator.ex
│   ├── parsers/
│   │   ├── csv_parser.ex
│   │   ├── json_parser.ex
│   │   └── log_parser.ex
│   └── metrics/
│       ├── csv_metrics.ex
│       ├── json_metrics.ex
│       └── log_metrics.ex
├── data/
└── test/
```

---

## 11) Dependencies

This project uses external libraries for parsing:

- **JSON**: `Jason`
- **CSV**: `NimbleCSV`

---

## 12) Tests

Tests are implemented with **ExUnit** and cover:  

- Directory processing
- Single-file processing
- Mixed input lists
- Invalid path handling
- Correct report generation
- Progress reporting
- Benchmark comparison
- Returning supported file types
- Keep progress even if unsupported file types
- Duplicated files
Run tests:

```bash
mix test
```

---

## 13) Design Notes

- Parallel mode uses a simple model: **1 file = 1 process**, effective for medium-sized batches.
- To avoid out-of-order results, each file keeps an index and results are re-ordered at the end.
- The report format stays the same in both modes, using a single `ReportGenerator`.

---

14) Execution

To create a executable file, run:

```bash
mix escript.build
```

15) Usage

To run the executable file, use:

```bash
./file_processor data 
```
