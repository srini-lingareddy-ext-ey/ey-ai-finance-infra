# Time Series Comparison Endpoint

Generate time series comparison data for charting by evaluating a formula across multiple series and time period buckets (monthly, quarterly, or custom).

## Endpoint
```
POST /fdm/read/ts-comparison
```

## Overview

The Time Series Comparison endpoint allows you to:
- Define named variables that each aggregate a line item per time period bucket
- Write a formula using `{{VARIABLE}}` placeholders evaluated per bucket per series
- Choose a breakdown type: `monthly`, `quarterly`, or `custom`
- Define 1–4 data series with independent date ranges, version codes, and filters
- Support fiscal year offsets for quarterly breakdowns (e.g., fiscal year starting in July)
- Compare trends across years, versions, or entity/geography slices
- Support multiple aggregation types: `sum`, `avg`, `min`, `max`, `count`, `point_in_time_latest_sum`, `point_in_time_weighted_avg`
- Validate the requested unit of measure against the underlying fact data

## Request Model

### `TSComparisonRequest`

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `tenant_id` | `int` | Yes | Tenant ID to query |
| `variables` | `Dict[str, TSComparisonVariable]` | Yes | Named variables (keys must be `A-Z0-9_`) |
| `formula` | `str` | Yes | Math formula using `{{VARIABLE}}` placeholders |
| `label` | `str` | Yes | Display label for the comparison |
| `unit` | `str` | Yes | Expected unit of measure (validated against fact data) |
| `breakdown` | `"monthly" \| "quarterly" \| "custom"` | Yes | How to slice the time periods |
| `fiscal_year_start_month` | `int` | No | Month (1–12) the fiscal year starts. Defaults to `1` (January). Only affects quarterly breakdown. Example: `7` = Jul fiscal year → Q1=Jul-Sep |
| `series` | `List[TSComparisonSeriesDef]` | Yes | Data series to compare (1–4) |
| `cache` | `bool` | No | Whether to cache results (default: `false`) |

### `TSComparisonVariable`

Each variable produces a value per period bucket per series by aggregating a line item.

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `line_item_code` | `str` | Yes | Line item code to aggregate (e.g., `"net_revenue"`) |
| `aggregation` | `AggregationType` | Yes | Aggregation method (see below) |
| `weight_line_item_code` | `Optional[str]` | No | Weight line item code (required for `point_in_time_weighted_avg`) |

### `AggregationType`

| Value | Description |
|-------|-------------|
| `sum` | Sum of all matching values in the period |
| `avg` | Mean of all matching values in the period |
| `min` | Minimum value in the period |
| `max` | Maximum value in the period |
| `count` | Count of matching rows in the period |
| `point_in_time_latest_sum` | Sum of values at the latest date within the period |
| `point_in_time_weighted_avg` | Weighted average at the latest date (requires `weight_line_item_code`) |

### `TSComparisonSeriesDef`

Each series shares the same formula and variables but can differ in date range, version codes, and dimension filters.

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `label` | `str` | Yes | Display label for the series (e.g., `"2025 Actuals"`) |
| `period` | `DatePeriod` | Conditional | Date range to auto-slice. Required when breakdown is `monthly` or `quarterly`. Must be `null` when breakdown is `custom`. |
| `custom_periods` | `List[TSComparisonCustomDatePeriod]` | Conditional | Explicit period buckets. Required when breakdown is `custom`. Must be `null` when breakdown is `monthly` or `quarterly`. |
| `version_codes` | `List[str]` | Yes | Version filter (min 1, e.g., `["Actuals"]`) |
| `geography_codes` | `Optional[List[str]]` | No | Optional geography filter. `null` = all |
| `entity_codes` | `Optional[List[str]]` | No | Optional entity filter. `null` = all |

### `TSComparisonCustomDatePeriod`

Used only when `breakdown` is `"custom"`.

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `label` | `str` | Yes | Display label for the period (e.g., `"H1"`, `"Week 1"`) |
| `start_date` | `date` | Yes | Start date (inclusive) |
| `end_date` | `date` | Yes | End date (inclusive) |

### `DatePeriod`

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `start_date` | `date` | Yes | Start date (inclusive) |
| `end_date` | `date` | Yes | End date (inclusive) |

## Response Model

### `TSComparisonResponse`

| Field | Type | Description |
|-------|------|-------------|
| `label` | `str` | Display label for the comparison |
| `units` | `str` | Unit of measure |
| `formula` | `str` | The formula used |
| `breakdown` | `"monthly" \| "quarterly" \| "custom"` | Breakdown type used |
| `period_labels` | `List[str]` | Aligned period labels across all series (e.g., `["Jan", "Feb", ...]`) |
| `series` | `List[TSComparisonSeriesResult]` | One result per series |

### `TSComparisonSeriesResult`

| Field | Type | Description |
|-------|------|-------------|
| `label` | `str` | Series display label |
| `data_points` | `List[TSComparisonDataPoint]` | One data point per period bucket |

### `TSComparisonDataPoint`

| Field | Type | Description |
|-------|------|-------------|
| `period_label` | `str` | Period label (e.g., `"Jan"`, `"Q1"`, `"H1"`) |
| `period_start` | `date` | Period start date |
| `period_end` | `date` | Period end date |
| `value` | `float \| null` | Computed value (`null` if calculation failed) |

## Breakdown Types

### Monthly

Automatically slices the series `period` into calendar month buckets.

- Period labels: `Jan`, `Feb`, `Mar`, ..., `Dec`
- Each bucket spans first day to last day of that month
- Partial months are supported (clamped to the period's start/end)

### Quarterly

Automatically slices the series `period` into fiscal quarter buckets.

- Period labels: `Q1`, `Q2`, `Q3`, `Q4`
- Respects `fiscal_year_start_month`:
  - `1` (default) → Calendar quarters: Q1=Jan-Mar, Q2=Apr-Jun, Q3=Jul-Sep, Q4=Oct-Dec
  - `7` → Fiscal quarters: Q1=Jul-Sep, Q2=Oct-Dec, Q3=Jan-Mar, Q4=Apr-Jun
- Partial quarters are supported (clamped to the period's start/end)

### Custom

Uses explicitly defined `custom_periods` on each series. All series must have the **same number** of custom periods.

## Formula System

### Formula Syntax

Formulas use `{{VARIABLE}}` placeholders that reference variables defined in the `variables` dict. The formula is evaluated once per period bucket per series.

**Allowed operations:**
- Addition: `+`
- Subtraction: `-`
- Multiplication: `*`
- Division: `/`
- Parentheses: `()`
- Numbers: `0-9`, `.`

**Examples:**
```
"{{NET_REV}}"                                    # Simple variable
"{{NET_REV}} - {{COGS}}"                        # Gross profit
"({{NET_REV}} - {{COGS}}) / {{NET_REV}} * 100" # Gross margin %
"{{PRODUCT_REV}} + {{SERVICE_REV}}"            # Total revenue
```

### Allowed Characters

Formulas are validated to only contain: digits, `+`, `-`, `*`, `/`, `(`, `)`, `.`, spaces, and `{{A-Z0-9_}}` placeholders. Evaluated via AST-protected safe math evaluation (no `eval()`).

## Examples

### Example 1: Monthly Revenue Trend — YoY Comparison

Compare 2025 Actuals vs 2024 Actuals monthly.

**Request:**
```json
{
    "tenant_id": 1,
    "label": "Net Revenue Monthly Trend",
    "unit": "USD",
    "formula": "{{NET_REV}}",
    "breakdown": "monthly",
    "cache": false,

    "variables": {
        "NET_REV": {
            "line_item_code": "net_revenue",
            "aggregation": "sum"
        }
    },

    "series": [
        {
            "label": "2025 Actuals",
            "period": {
                "start_date": "2025-01-01",
                "end_date": "2025-12-31"
            },
            "version_codes": ["Actuals"],
            "geography_codes": ["North America", "Europe"]
        },
        {
            "label": "2024 Actuals",
            "period": {
                "start_date": "2024-01-01",
                "end_date": "2024-12-31"
            },
            "version_codes": ["Actuals"],
            "geography_codes": ["North America", "Europe"]
        }
    ]
}
```

**Response:**
```json
{
    "label": "Net Revenue Monthly Trend",
    "units": "USD",
    "formula": "{{NET_REV}}",
    "breakdown": "monthly",
    "period_labels": ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"],
    "series": [
        {
            "label": "2025 Actuals",
            "data_points": [
                {
                    "period_label": "Jan",
                    "period_start": "2025-01-01",
                    "period_end": "2025-01-31",
                    "value": 4500000.0
                },
                {
                    "period_label": "Feb",
                    "period_start": "2025-02-01",
                    "period_end": "2025-02-28",
                    "value": 4700000.0
                }
            ]
        },
        {
            "label": "2024 Actuals",
            "data_points": [
                {
                    "period_label": "Jan",
                    "period_start": "2024-01-01",
                    "period_end": "2024-01-31",
                    "value": 4200000.0
                },
                {
                    "period_label": "Feb",
                    "period_start": "2024-02-01",
                    "period_end": "2024-02-29",
                    "value": 4350000.0
                }
            ]
        }
    ]
}
```

### Example 2: Quarterly Gross Margin — Actuals vs Budget

Compare Actuals vs Budget quarterly with a multi-variable formula.

**Request:**
```json
{
    "tenant_id": 1,
    "label": "Gross Margin Quarterly",
    "unit": "USD",
    "formula": "{{NET_REV}} - {{COGS}}",
    "breakdown": "quarterly",
    "fiscal_year_start_month": 1,
    "cache": false,

    "variables": {
        "NET_REV": {
            "line_item_code": "net_revenue",
            "aggregation": "sum"
        },
        "COGS": {
            "line_item_code": "cogs_total",
            "aggregation": "sum"
        }
    },

    "series": [
        {
            "label": "Actuals",
            "period": {
                "start_date": "2025-01-01",
                "end_date": "2025-12-31"
            },
            "version_codes": ["Actuals"]
        },
        {
            "label": "Budget",
            "period": {
                "start_date": "2025-01-01",
                "end_date": "2025-12-31"
            },
            "version_codes": ["AOP"]
        }
    ]
}
```

**Response:**
```json
{
    "label": "Gross Margin Quarterly",
    "units": "USD",
    "formula": "{{NET_REV}} - {{COGS}}",
    "breakdown": "quarterly",
    "period_labels": ["Q1", "Q2", "Q3", "Q4"],
    "series": [
        {
            "label": "Actuals",
            "data_points": [
                {
                    "period_label": "Q1",
                    "period_start": "2025-01-01",
                    "period_end": "2025-03-31",
                    "value": 1580000.0
                },
                {
                    "period_label": "Q2",
                    "period_start": "2025-04-01",
                    "period_end": "2025-06-30",
                    "value": 1720000.0
                }
            ]
        },
        {
            "label": "Budget",
            "data_points": [
                {
                    "period_label": "Q1",
                    "period_start": "2025-01-01",
                    "period_end": "2025-03-31",
                    "value": 1600000.0
                },
                {
                    "period_label": "Q2",
                    "period_start": "2025-04-01",
                    "period_end": "2025-06-30",
                    "value": 1750000.0
                }
            ]
        }
    ]
}
```

### Example 3: Custom Periods — Half-Year Comparison

Compare H1 vs H2 using explicit custom period buckets.

**Request:**
```json
{
    "tenant_id": 1,
    "label": "Revenue H1 vs H2",
    "unit": "USD",
    "formula": "{{REV}}",
    "breakdown": "custom",
    "cache": false,

    "variables": {
        "REV": {
            "line_item_code": "net_revenue",
            "aggregation": "sum"
        }
    },

    "series": [
        {
            "label": "2025 Actuals",
            "custom_periods": [
                {
                    "label": "H1",
                    "start_date": "2025-01-01",
                    "end_date": "2025-06-30"
                },
                {
                    "label": "H2",
                    "start_date": "2025-07-01",
                    "end_date": "2025-12-31"
                }
            ],
            "version_codes": ["Actuals"]
        }
    ]
}
```

### Example 4: Weighted Average with `point_in_time_weighted_avg`

Track volume-weighted average price monthly.

**Request:**
```json
{
    "tenant_id": 1,
    "label": "Weighted Avg Price Monthly",
    "unit": "USD",
    "formula": "{{W_PRICE}}",
    "breakdown": "monthly",
    "cache": false,

    "variables": {
        "W_PRICE": {
            "line_item_code": "unit_price",
            "aggregation": "point_in_time_weighted_avg",
            "weight_line_item_code": "volume"
        }
    },

    "series": [
        {
            "label": "2025 Actuals",
            "period": {
                "start_date": "2025-01-01",
                "end_date": "2025-06-30"
            },
            "version_codes": ["Actuals"]
        }
    ]
}
```

## Key Features

### Single Collect Architecture

All variable aggregations (one per series × bucket × variable) plus unit validation are computed in a **single Polars `.collect()` call**. This means:
- Only one pass over the fact data regardless of how many variables, series, or buckets are defined
- Polars parallelizes aggregation expressions internally
- Minimal memory overhead — no intermediate DataFrames

### Breakdown Auto-Slicing

For `monthly` and `quarterly` breakdowns, period buckets are generated automatically from the series `period`. No need to manually specify each month or quarter — just provide the overall date range.

### Fiscal Year Support

The `fiscal_year_start_month` field controls quarterly bucket alignment:
- `1` (default): Calendar quarters (Q1=Jan-Mar)
- `4`: UK fiscal year (Q1=Apr-Jun)
- `7`: US federal fiscal year (Q1=Jul-Sep)
- `10`: Australian fiscal year (Q1=Oct-Dec)

### Multi-Series Comparison

Up to 4 series can be defined per request. Common patterns:
- **Year-over-year**: Same filters, different date ranges
- **Actuals vs Budget**: Same date range, different version codes
- **Regional comparison**: Same dates/versions, different geography filters

### Weighted Average (Self-Join Pattern)

When using `point_in_time_weighted_avg`:
1. The `weight_line_item_code` rows are included in the prepared facts
2. A self-join adds `{weight_code}_weight` columns alongside each fact row
3. The aggregation computes `sum(value × weight) / sum(weight)` at the latest date in each bucket
4. Division by zero is guarded — returns `0.0` if weight sum is zero
5. Requires `weight_line_item_code` on the variable (validated by model)

### Unit Validation

The `unit` field on the request is validated against the actual `unit_of_measure` values in the fact data. If no matching unit is found, the error response includes the list of available units. This prevents silent mismatches.

### Empty Data Validation

If no fact data is found for the requested line item codes and date range, the endpoint returns a clear error identifying the missing codes and date range — rather than failing with a misleading unit validation error.

### Preagg-First with Legacy Fallback

The endpoint first attempts to load pre-aggregated enriched facts (codes already denormalized). If unavailable, it falls back to joining raw fact + dimension tables. Both paths produce the same LazyFrame schema.

## Error Handling

### Common Errors

| Error Type | HTTP Status | When It Occurs |
|------------|-------------|----------------|
| Tenant not found | 404 | Invalid `tenant_id` |
| Invalid variable name | 422 | Variable key not matching `^[A-Z0-9_]+$` |
| Invalid formula characters | 422 | Formula contains disallowed characters |
| Missing `weight_line_item_code` | 422 | `point_in_time_weighted_avg` without weight code |
| Breakdown/series mismatch | 422 | Series provides `period` when breakdown is `custom`, or vice versa |
| Unequal custom period counts | 422 | Custom series have different numbers of periods |
| Duplicate filter codes | 422 | Duplicate values in `geography_codes`, `entity_codes`, or `version_codes` |
| Too many series | 422 | More than 4 series |
| No fact data found | 500 | Line item codes not found in fact data for the given date range |
| Unit mismatch | 500 | `unit` not found in fact data (includes available units in error) |
| Formula evaluation failure | N/A | Per-bucket formula errors produce `null` values (non-fatal) |

### Error Response Format

```json
{
    "detail": "Failed to generate time series comparison: No fact data found for line item codes ['INVALID_CODE'] in date range 2025-01-01 to 2025-12-31"
}
```

```json
{
    "detail": "Failed to generate time series comparison: Unit 'EUR' not found in fact data for the requested variables. Available units: ['USD', 'count']"
}
```

## Validation Rules

### Variable Names
- Must match `^[A-Z0-9_]+$` (uppercase letters, digits, underscores only)
- Used as keys in the `variables` dict

### Formulas
- Uses `{{VARIABLE}}` references matching the variable dict keys
- Validated against: `^[0-9\s+\-*/()\.\{\}A-Z_]+$`
- Evaluated via AST-protected safe math evaluation (no `eval()`)

### Breakdown Consistency
- `monthly` / `quarterly` → each series must provide `period`, must not provide `custom_periods`
- `custom` → each series must provide `custom_periods`, must not provide `period`
- All custom series must have the same number of periods

### Filter Uniqueness
- `version_codes`, `geography_codes`, and `entity_codes` must not contain duplicates
