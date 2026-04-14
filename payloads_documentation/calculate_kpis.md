# KPI Calculation Endpoint

Calculate 1 to many KPIs in a single request using formula-based variables.

## Endpoint
```
POST /fdm/read/calculate-kpi
```

## Overview

The KPI calculation engine allows you to:
- Define variables that fetch and aggregate fact data
- Write mathematical formulas using those variables
- Calculate multiple KPIs efficiently in one request (data loaded once)
- Return YoY, MoM, or other comparison metrics

## Request Model

### `KpiBatchCalculationRequest`

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `tenant_id` | `int` | Yes | Tenant ID to query |
| `kpis` | `List[KpiCalculationRequest]` | Yes | List of KPIs to calculate (1-50) |

### `KpiCalculationRequest`

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `variables` | `Dict[str, KpiRequestVariable]` | Yes | Named variables for data fetching |
| `value_formula` | `str` | Yes | Formula for main KPI value (e.g., `"{{REV_2024}}"`) |
| `change_formula` | `str` | No | Formula for change calculation (e.g., YoY %) |
| `label` | `str` | Yes | Display label for KPI |
| `value_units` | `str` | Yes | Units for display (e.g., `"$"`, `"%"`, `"USD"`) |
| `change_label` | `str` | No | Label for change value (e.g., `"vs. prior year"`) |

### `KpiRequestVariable`

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `line_item_code` | `str` | Yes | Line item code to fetch (e.g., `"REVENUE"`) |
| `start_date` | `date` | Yes | Start date (inclusive) |
| `end_date` | `date` | Yes | End date (inclusive) |
| `aggregation` | `"sum" \| "avg" \| "min" \| "max" \| "count"` | Yes | Aggregation method |
| `geography_codes` | `List[str]` | No | Filter by geography codes |
| `entity_codes` | `List[str]` | No | Filter by entity codes |
| `version_codes` | `List[str]` | No | Filter by version codes (e.g., `["ACTUAL"]`) |

## Response Model

### `CalculateKpisBatchResponse`

| Field | Type | Description |
|-------|------|-------------|
| `kpis` | `List[Kpi]` | Successfully calculated KPIs |
| `errors` | `List[Dict[str, str]]` | List of calculation errors |

### `Kpi`

| Field | Type | Description |
|-------|------|-------------|
| `label` | `str` | KPI display label |
| `value` | `float` | Calculated value |
| `units` | `str` | Display units |
| `change` | `ChangeValue` | Change metric (always present, may be 0.0) |

### `ChangeValue`

| Field | Type | Description |
|-------|------|-------------|
| `value` | `float` | Change value (e.g., percentage) |
| `postValueText` | `str` | Label text (e.g., `"vs. prior year"`) |

## Formula Syntax

Variables are referenced using `{{VARIABLE_NAME}}` placeholders:

**Allowed operations:**
- Addition: `+`
- Subtraction: `-`
- Multiplication: `*`
- Division: `/`
- Parentheses: `()`
- Numbers: `0-9`, `.`

**Not allowed:**
- Function calls
- Variables without `{{ }}`
- Letters outside placeholders
- Any code execution

**Examples:**
```python
"{{REV_2024}}"                                           // Simple variable
"{{REV_2024}} * 2"                                       // Multiply by constant
"{{PROD_REV}} + {{SERV_REV}}"                           // Add variables
"(({{REV_2024}} - {{REV_2023}}) / {{REV_2023}}) * 100" // YoY % change
"({{PROD_REV}} / {{REVENUE}}) * 100"                    // Percentage of total
```

## Examples

### Example 1: Single KPI with Year Half 1 vs Year Half 2 Comparison

**Request:**
```json
{
  "tenant_id": 1,
  "kpis": [
    {
      "variables": {
        "REV_H1_2024": {
          "line_item_code": "REVENUE",
          "start_date": "2024-01-01",
          "end_date": "2024-06-01",
          "aggregation": "sum",
          "geography_codes": ["USA"],
          "entity_codes": ["SALES"],
          "version_codes": ["ACTUAL"]
        },
        "REV_H2_2024": {
          "line_item_code": "REVENUE",
          "start_date": "2024-07-01",
          "end_date": "2024-12-01",
          "aggregation": "sum",
          "geography_codes": ["USA"],
          "entity_codes": ["SALES"],
          "version_codes": ["ACTUAL"]
        }
      },
      "value_formula": "{{REV_H2_2024}}",
      "change_formula": "(({{REV_H2_2024}} - {{REV_H1_2024}}) / {{REV_H1_2024}}) * 100",
      "label": "2024 H2 USA Sales Revenue",
      "value_units": "USD",
      "change_label": "vs. 2024 H1"
    }
  ]
}
```

**Response:**
```json
{
  "kpis": [
    {
      "label": "2024 H2 USA Sales Revenue",
      "value": 150000.0,
      "units": "USD",
      "change": {
        "value": 25.0,
        "postValueText": "vs. 2024 H1"
      }
    }
  ],
  "errors": null
}
```

### Example 2: Multiple KPIs with Errors (Partial Success)

**Request:**
```json
{
  "tenant_id": 1,
  "kpis": [
    {
      "variables": {
        "REV_H1_2024": {
          "line_item_code": "REVENUE",
          "start_date": "2024-01-01",
          "end_date": "2024-06-01",
          "aggregation": "sum",
          "geography_codes": ["USA"],
          "entity_codes": ["SALES"],
          "version_codes": ["ACTUAL"]
        },
        "REV_H2_2024": {
          "line_item_code": "REVENUE",
          "start_date": "2024-07-01",
          "end_date": "2024-12-01",
          "aggregation": "sum",
          "geography_codes": ["USA"],
          "entity_codes": ["SALES"],
          "version_codes": ["ACTUAL"]
        }
      },
      "value_formula": "{{REV_H2_2024}}",
      "change_formula": "(({{REV_H2_2024}} - {{REV_H1_2024}}) / {{REV_H1_2024}}) * 100",
      "label": "2024 H2 USA Sales Revenue",
      "value_units": "USD",
      "change_label": "vs. 2024 H1"
    },
    {
      "variables": {
        "FAKE_LINE_ITEM": {
          "line_item_code": "THIS_DOES_NOT_EXIST",
          "start_date": "2024-01-01",
          "end_date": "2024-12-31",
          "aggregation": "sum",
          "geography_codes": null,
          "entity_codes": null,
          "version_codes": null
        }
      },
      "value_formula": "{{FAKE_LINE_ITEM}}",
      "change_formula": null,
      "label": "Invalid Line Item Test",
      "value_units": "$",
      "change_label": null
    },
    {
      "variables": {
        "REV_2024": {
          "line_item_code": "REVENUE",
          "start_date": "2024-01-01",
          "end_date": "2024-12-31",
          "aggregation": "sum",
          "geography_codes": null,
          "entity_codes": null,
          "version_codes": null
        }
      },
      "value_formula": "{{REV_2024}} + {{UNDEFINED_VARIABLE}}",
      "change_formula": null,
      "label": "Undefined Variable Test",
      "value_units": "$",
      "change_label": null
    },
    {
      "variables": {
        "ZERO_REV": {
          "line_item_code": "REVENUE",
          "start_date": "2099-01-01",
          "end_date": "2099-12-31",
          "aggregation": "sum",
          "geography_codes": null,
          "entity_codes": null,
          "version_codes": null
        }
      },
      "value_formula": "100 / {{ZERO_REV}}",
      "change_formula": null,
      "label": "Division by Zero Test",
      "value_units": "%",
      "change_label": null
    }
  ]
}
```

**Response:**
```json
{
  "kpis": [
    {
      "change": {
        "postValueText": "vs. 2024 H1",
        "value": 24.576271186440678
      },
      "label": "2024 H2 USA Sales Revenue",
      "value": 1470000,
      "units": "USD"
    }
  ],
  "errors": [
    {
      "kpi_index": "1",
      "label": "Invalid Line Item Test",
      "error": "Invalid line_item_code: 'THIS_DOES_NOT_EXIST'. Available: COGS, EXPENSES, PROD_REV, REVENUE, SERV_REV"
    },
    {
      "kpi_index": "2",
      "label": "Undefined Variable Test",
      "error": "Formula references undefined variables: UNDEFINED_VARIABLE. Defined variables: REV_2024"
    },
    {
      "kpi_index": "3",
      "label": "Division by Zero Test",
      "error": "Formula Evaluation Failed: float division by zero"
    }
  ]
}
```

## Error Handling

The endpoint supports **partial success** - if some KPIs fail, successful ones are still returned with error explanations in errors list.

### Common Errors

| Error Type | HTTP Status | When It Occurs |
|------------|-------------|----------------|
| Tenant not found | 404 | Invalid `tenant_id` |
| No data for tenant | 404 | Tenant has no facts/dimensions |
| All KPIs failed | 400 | Every KPI in request failed validation/calculation |
| Invalid line item code | 400 | Variable references non-existent line item |
| Undefined variable | 400 | Formula references variable not in `variables` dict |
| Division by zero | 400 | Formula divides by zero (or variable with 0.0 value) |
| Invalid formula syntax | 400 | Formula contains disallowed characters or operations |

### Error Response Structure

When **all KPIs fail**, endpoint returns 400:
```json
{
  "detail": {
    "message": "All KPI calculations failed",
    "errors": [
      {
        "kpi_index": 0,
        "label": "KPI Label",
        "error": "Error message"
      }
    ]
  }
}
```

When **some KPIs succeed**, endpoint returns 200 with errors in metadata (see Example 2).

## Performance

- **Data loading:** ~200ms (done once for all KPIs, lazyframe loading with polars)
- **Per KPI calculation:** ~50ms
- **10 KPIs:** ~700ms total vs. ~2000ms for 10 separate requests
- **Speedup:** 3-7x faster for batch requests

## Security

Formulas are evaluated using a safe AST parser with triple-layer protection:
1. **Regex whitelist** - Only allows numbers and operators
2. **Letter blocking** - Prevents variable names and function calls
3. **AST whitelist** - Only allows whitelisted arithmetic operations

**Not possible:**
- Code injection
- Function calls
- Variable access
- File system access
- Network requests