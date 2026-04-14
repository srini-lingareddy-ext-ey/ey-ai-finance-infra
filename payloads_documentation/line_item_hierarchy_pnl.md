# Line Item Hierarchy PnL Table Endpoint

Generate Profit & Loss tables with hierarchical line items as rows, showing actuals vs versions vs prior year comparisons.

## Endpoint
```
POST /fdm/read/pnl-table/line-item-hierarchy
```

## Overview

The Line Item Hierarchy PnL endpoint allows you to:
- Build P&L tables with line items organized in parent-child hierarchies
- Automatically include child line items when a parent is selected
- Compare multiple versions (Actuals, Budget, Forecast) side-by-side
- Calculate percentage changes between columns
- Apply filters by entity, geography, and version
- Cache results for faster subsequent requests

## Request Model

### `LineItemHierarchyPnLRequest`

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `tenant_id` | `int` | Yes | Tenant ID to query |
| `table_label` | `str` | Yes | Display label for the table |
| `line_items` | `List[LineItemConfig]` | Yes | Line items to include (1-50) |
| `filters` | `Optional[PnLFilters]` | No | Optional filters for entities, geographies |
| `period` | `DatePeriod` | Yes | Date range for the table |
| `main_column` | `PnLColumnRequest` | Yes | Primary column configuration |
| `comparison_columns` | `List[PnLColumnRequest]` | Yes | Additional columns for comparison (1-5) |
| `override_row_names` | `Optional[List[OverrideRowNameConfig]]` | No | Custom row name overrides |
| `cache_table` | `bool` | No | Whether to cache results (default: `true`) |

### `LineItemConfig`

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `line_item_code` | `str` | Yes | Line item code (e.g., `"REVENUE"`, `"COGS"`) |
| `aggregation` | `"sum" \| "avg" \| "min" \| "max" \| "count"` | Yes | Aggregation method |
| `include_children` | `bool` | No | Auto-include all child line items (default: `false`) |

### `PnLFilters`

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `entity_codes` | `List[str]` | No | Filter by specific entities |
| `geography_codes` | `List[str]` | No | Filter by specific geographies |
| `version_codes` | `List[str]` | No | Filter by specific versions |

### `DatePeriod`

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `start_date` | `date` | Yes | Start date (inclusive) |
| `end_date` | `date` | Yes | End date (inclusive) |

### `PnLColumnRequest`

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `label` | `str` | Yes | Column display label |
| `version_code` | `str` | Yes | Version code (e.g., `"ACTUALS"`, `"BUDGET"`) |
| `show_percent_change` | `bool` | No | Show % change vs main column (default: `true`) |
| `period` | `DatePeriod` | No | Override date period for this column |

### `OverrideRowNameConfig`

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `code` | `str` | Yes | Line item code to override |
| `row_type` | `"entity" \| "line_item" \| "custom"` | Yes | Type of row |
| `name_override` | `str` | Yes | Custom display name |

## Response Model

### `PnLTableV2`

| Field | Type | Description |
|-------|------|-------------|
| `table_label` | `str` | Table display label |
| `column_labels` | `List[str]` | Column labels in order |
| `rows` | `List[PnLRowV2]` | Hierarchical rows with data from all requests |

### `PnLRowV2`

| Field | Type | Description |
|-------|------|-------------|
| `row_number` | `int` | Uniqie Row Index in table |
| `row_type` | `str` | Row type (`"line_item"`, `"entity"`, `"custom"`) |
| `code` | `str` | Entity or line item code |
| `name` | `str` | Row display label / Object Name |
| `id` | `int \| None` | Unique object identifier (renumbered globally) (Entity vs Line Item Can Cause overlap) |
| `level` | `int` | Hierarchy level (0 = root) |
| `parent_id` | `int \| None` | Parent row ID (None for root, renumbered) |
| `measures` | `str \| None` | Unit of measure |
| `columns` | `Dict[str, PnLCellValue]` | Column values keyed by column label {column_label: {PnLCell}} |
| `entity_rollup` | `str` | Entity Aggregation Rollup Type (`"sum"`, `"avg"`, `"min"`, `"max"`) |

### `PnLCellValue`

| Field | Type | Description |
|-------|------|-------------|
| `value` | `float \| None` | Cell value |
| `percentChange` | `float \| None` | Percentage change vs main column |

## Examples

### Example: Might Devs Main Overview PnL Table

**Request:**
```json
{
    "tenant_id": 1,
    "table_label": "Mighty Ducts Consolidated PnL",
    "cache_table": false,

    "line_items": [
        {
            "line_item_code": "volume",
            "aggregation": "sum"
        },
        {
            "line_item_code": "net_revenue",
            "aggregation": "sum"
        },
        {
            "line_item_code": "cogs_total",
            "aggregation": "sum"
        },
        {
            "line_item_code": "net_margin",
            "aggregation": "sum"
        }
    ],
    "filters": {
        "geography_codes": ["North America", "Europe"]
    },
    "period": {
        "start_date": "2025-01-01",
        "end_date": "2025-06-01"
    },
    "main_column": {
        "label": "Actuals",
        "version_code": "Actuals",
        "period": {
            "start_date": "2025-01-01",
            "end_date": "2025-06-01"
        },
        "show_percent_change": false
    },
    "comparison_columns": [
        {
            "label": "VS. AOP",
            "version_code": "AOP",
            "show_percent_change": true,
            "period": {
                "start_date": "2025-01-01",
                "end_date": "2025-06-01"
            }
        },
        {
            "label": "VS. FORECAST",
            "version_code": "Forecast Old",
            "show_percent_change": true,
            "period": {
                "start_date": "2025-01-01",
                "end_date": "2025-06-01"
            }
        },
        {
            "label": "VS. PRIOR YEAR",
            "version_code": "Actuals",
            "show_percent_change": true,
            "period": {
                "start_date": "2024-01-01",
                "end_date": "2024-06-01"
            }
        }
    ]
}
```

**Response:**
```json
{
  "table_label": "Mighty Ducts Consolidated PnL",
  "column_labels": [
    "Actuals",
    "VS. AOP",
    "VS. FORECAST",
    "VS. PRIOR YEAR"
  ],
  "rows": [
    {
      "row_type": "line_item",
      "code": "volume",
      "name": "Volume",
      "id": 18,
      "level": 0,
      "parent_id": null,
      "measures": "units",
      "columns": {
        "Actuals": {
          "value": 623780.8282601002,
          "percent_change": null
        },
        "VS. AOP": {
          "value": 628832.7221092001,
          "percent_change": -0.8033764261113916
        },
        "VS. FORECAST": {
          "value": 625788.6034943999,
          "percent_change": -0.3208392136079671
        },
        "VS. PRIOR YEAR": {
          "value": 587580.7460157,
          "percent_change": 6.160869376654644
        }
      },
      "entity_rollup": "sum"
    },
    {
      "row_type": "line_item",
      "code": "net_revenue",
      "name": "Net Revenue",
      "id": 13,
      "level": 0,
      "parent_id": null,
      "measures": "USD",
      "columns": {
        "Actuals": {
          "value": 28441921483.495705,
          "percent_change": null
        },
        "VS. AOP": {
          "value": 28431755314.063,
          "percent_change": 0.035756390417711933
        },
        "VS. FORECAST": {
          "value": 28337975591.5625,
          "percent_change": 0.36680775448248343
        },
        "VS. PRIOR YEAR": {
          "value": 27923751456.17139,
          "percent_change": 1.8556605051352943
        }
      },
      "entity_rollup": "sum"
    },
    {
      "row_type": "line_item",
      "code": "cogs_total",
      "name": "COGS - Total",
      "id": 6,
      "level": 0,
      "parent_id": null,
      "measures": "USD",
      "columns": {
        "Actuals": {
          "value": 22123762547.362705,
          "percent_change": null
        },
        "VS. AOP": {
          "value": 22117458202.6563,
          "percent_change": 0.02850392955935818
        },
        "VS. FORECAST": {
          "value": 22044048943.9063,
          "percent_change": 0.36161053561097767
        },
        "VS. PRIOR YEAR": {
          "value": 21531770559.341805,
          "percent_change": 2.7493883347370995
        }
      },
      "entity_rollup": "sum"
    },
    {
      "row_type": "line_item",
      "code": "net_margin",
      "name": "Net Margin",
      "id": 12,
      "level": 0,
      "parent_id": null,
      "measures": "USD",
      "columns": {
        "Actuals": {
          "value": 3829237326.1366396,
          "percent_change": null
        },
        "VS. AOP": {
          "value": 3827096848.3174667,
          "percent_change": 0.055929544090683056
        },
        "VS. FORECAST": {
          "value": 3814301681.5679173,
          "percent_change": 0.3915695667413166
        },
        "VS. PRIOR YEAR": {
          "value": 3920656585.4339395,
          "percent_change": -2.331733404984807
        }
      },
      "entity_rollup": "sum"
    }
  ]
}
```

## Key Features

### Automatic Child Inclusion

When `include_children: true` is set, the endpoint automatically:
1. Traverses the line item hierarchy
2. Includes all descendant line items
3. Maintains proper parent-child relationships
4. Preserves hierarchy levels

### Percentage Change Calculation

For comparison columns with `show_percent_change: true`:
- Formula: `((main_value - comparison_value) / comparison_value) * 100`
- Returns `null` if either value is `null`
- Returns `null` if comparison value is `0.0` (division by zero)

### Caching

When `cache_table: true`:
- Generated tables are cached using a SHA256 hash of request parameters
- Subsequent identical requests return cached results (faster)
- Cache key excludes: `table_label`, `override_row_names`, `cache_table` flag
- Background task stores cache after response is sent

## Error Handling

### Common Errors

| Error Type | HTTP Status | When It Occurs |
|------------|-------------|----------------|
| Tenant not found | 404 | Invalid `tenant_id` |
| No data for tenant | 404 | Tenant has no facts/dimensions |
| Invalid line item code | 400 | Line item doesn't exist in database |
| Invalid date range | 400 | `start_date` is after `end_date` |
| Too many line items | 400 | More than 50 line items requested |
| Too many comparison columns | 400 | More than 5 comparison columns |
| Invalid version code | 400 | Version doesn't exist in database |

### Error Response Format

```json
{
  "detail": "Tenant with ID 999 not found"
}
```

## Best Practices

1. **Use `include_children`** for parent line items to avoid manual hierarchy management
2. **Enable caching** for tables that don't change frequently
3. **Use period overrides** for YoY comparisons instead of separate requests
4. **Override row names** for better presentation without changing source data
