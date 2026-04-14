# Entity Hierarchy PnL Table Endpoint

Generate Profit & Loss tables with hierarchical entities (business units, segments) as rows, with calculated values based on line item formulas and automatic rollups.

## Endpoint
```
POST /fdm/read/pnl-table/entity-hierarchy
```

## Overview

The Entity Hierarchy PnL endpoint allows you to:
- Build P&L tables with entities organized in parent-child hierarchies
- Calculate entity values using formulas (e.g., `{{REVENUE}} - {{COGS}} - {{OPEX}}`)
- Automatically roll up child entity values to parent entities
- Compare multiple versions (Actuals, Budget, Forecast) side-by-side
- Override line items for specific entities
- Apply filters by geography and version
- Cache results for faster subsequent requests

## Request Model

### `EntityHierarchyPnLRequest`

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `tenant_id` | `int` | Yes | Tenant ID to query |
| `table_label` | `str` | Yes | Display label for the table |
| `root_entity_code` | `str` | Yes | Root entity code for hierarchy |
| `exclude_entity_codes` | `Optional[List[str]]` | No | Entity codes to exclude from hierarchy |
| `line_items` | `List[LineItemConfig]` | Yes | Line items used in formula (1-20) |
| `entity_line_item_overrides` | `Optional[Dict[str, List[str]]]` | No | Entity-specific line item overrides |
| `entity_formula` | `str` | Yes | Formula for calculating entity values |
| `entity_rollup` | `"sum" \| "avg" \| "min" \| "max"` | No | Parent rollup aggregation (default: `"sum"`) |
| `entity_rollup_measure` | `str` | Yes | Unit of measure for entity rollup |
| `geography_codes` | `Optional[List[str]]` | No | Optional filters for geographies |
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
| `include_children` | `bool` | No | Not used in entity hierarchy (ignored) |

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
| `code` | `str` | Yes | Entity or line item code to override |
| `row_type` | `"entity" \| "line_item" \| "custom"` | Yes | Type of row being overridden |
| `name_override` | `str` | Yes | Custom display name for the row |

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

## Formula Syntax

The `entity_formula` uses variable placeholders to reference line items:

**Allowed operations:**
- Addition: `+`
- Subtraction: `-`
- Multiplication: `*`
- Division: `/`
- Parentheses: `()`
- Numbers: `0-9`, `.`

**Variable format:** `{{LINE_ITEM_CODE}}`

**Examples:**
```python
"{{REVENUE}}"                                    # Simple variable
"{{REVENUE}} - {{COGS}}"                        # Gross profit
"{{REVENUE}} - {{COGS}} - {{OPEX}}"            # Net income
"({{REVENUE}} - {{COGS}}) / {{REVENUE}} * 100" # Gross margin %
"{{PRODUCT_REV}} + {{SERVICE_REV}}"            # Total revenue
```

## Examples

### Example 1: Mighty Devs Totals Subscribers Entity Hierarchy Table

**Request:**
```json
{
    "tenant_id": 2,
    "table_label": "Overview PNL Subscribers",
    "cache_table": false,
    "root_entity_code": "ROOT:All",
    "exclude_entity_codes": [
        "PRD:vCore390|PG:Compute|BU:Cloud Services",
        "PRD:vCore560|PG:Compute|BU:Cloud Services",
        "PRD:vCore830|PG:Compute|BU:Cloud Services",
        "PRD:xVault|PG:Storage|BU:Cloud Services",
        "PRD:yVault|PG:Storage|BU:Cloud Services",
        "PRD:zVault|PG:Storage|BU:Cloud Services",
        "PRD:Consulting|PG:Project Services|BU:Professional Services",
        "PRD:Implementation|PG:Project Services|BU:Professional Services",
        "PRD:Training|PG:Project Services|BU:Professional Services",
        "PRD:AppCare|PG:Managed Support|BU:Professional Services",
        "PRD:CloudAssist|PG:Managed Support|BU:Professional Services",
        "PRD:CloudShield|PG:Managed Support|BU:Professional Services",
        "PRD:DevAssist|PG:Managed Support|BU:Professional Services",
        "PRD:CollabPro|PG:Productivity Licenses|BU:Software Products",
        "PRD:MeetSync|PG:Productivity Licenses|BU:Software Products",
        "PRD:SyncBoard|PG:Productivity Licenses|BU:Software Products",
        "PRD:CodeSuite|PG:Developer Licenses|BU:Software Products",
        "PRD:DataFlow|PG:Developer Licenses|BU:Software Products",
        "PRD:ScriptLab|PG:Developer Licenses|BU:Software Products"
    ],
    "entity_formula": "{{paid_subscribers}}",
    "entity_rollup": "sum",
    "entity_rollup_measure": "count",
    "line_items": [
        {
        "line_item_code": "paid_subscribers",
        "aggregation": "sum"
        }
    ],
    "entity_line_item_overrides": null,
    "geography_codes": ["APAC", "EMEA", "North America"],
    "period": {
        "start_date": "2025-01-01",
        "end_date": "2025-06-30"
    },
    "main_column": {
        "label": "Actuals",
        "version_code": "Actual",
        "period": null,
        "show_percent_change": false
    },
    "comparison_columns": [
        {
            "label": "VS. AOP",
            "version_code": "AOP",
            "show_percent_change": true,
            "period": {
                "start_date": "2025-01-01",
                "end_date": "2025-06-30"
            }
        },
        {
            "label": "VS. FORECAST",
            "version_code": "3x9 Forecast",
            "show_percent_change": true,
            "period": {
                "start_date": "2025-01-01",
                "end_date": "2025-06-30"
            }
        },
        {
            "label": "VS. PRIOR YEAR",
            "version_code": "Actual",
            "show_percent_change": true,
            "period": {
                "start_date": "2024-01-01",
                "end_date": "2024-06-30"
            }
        }
    ],
    "override_row_names": [
        {
            "code": "ROOT:All",
            "row_type": "entity",
            "name_override": "Total Subscriptions"
        },
        {
            "code": "BU:Cloud Services",
            "row_type": "entity",
            "name_override": "Cloud"
        },
        {
            "code": "BU:Professional Services",
            "row_type": "entity",
            "name_override": "Support"
        },
        {
            "code": "BU:Software Products",
            "row_type": "entity",
            "name_override": "Software"
        }
    ]
}
```

**Response:**
```json
{
  "table_label": "Overview PNL Subscribers",
  "column_labels": [
    "Actuals",
    "VS. AOP",
    "VS. FORECAST",
    "VS. PRIOR YEAR"
  ],
  "rows": [
    {
      "row_type": "entity",
      "code": "ROOT:All",
      "name": "Total Subscriptions",
      "id": 0,
      "level": 0,
      "parent_id": null,
      "measures": "count",
      "columns": {
        "Actuals": {
          "value": 5423542.0198,
          "percent_change": null
        },
        "VS. AOP": {
          "value": 5492888,
          "percent_change": -1.2624684901640104
        },
        "VS. FORECAST": {
          "value": 5460523.4386,
          "percent_change": -0.6772504360769048
        },
        "VS. PRIOR YEAR": {
          "value": 5258947.8007000005,
          "percent_change": 3.129793740833306
        }
      },
      "entity_rollup": "sum"
    },
    {
      "row_type": "entity",
      "code": "BU:Software Products",
      "name": "Software",
      "id": 3,
      "level": 1,
      "parent_id": 0,
      "measures": "count",
      "columns": {
        "Actuals": {
          "value": 1565862,
          "percent_change": null
        },
        "VS. AOP": {
          "value": 1563018,
          "percent_change": 0.18195567805361165
        },
        "VS. FORECAST": {
          "value": 1575510,
          "percent_change": -0.6123731363177638
        },
        "VS. PRIOR YEAR": {
          "value": 1452574,
          "percent_change": 7.799120733263848
        }
      },
      "entity_rollup": "sum"
    },
    {
      "row_type": "entity",
      "code": "PG:Productivity Licenses|BU:Software Products",
      "name": "Productivity Licenses",
      "id": 9,
      "level": 2,
      "parent_id": 3,
      "measures": "count",
      "columns": {
        "Actuals": {
          "value": 878123,
          "percent_change": null
        },
        "VS. AOP": {
          "value": 879547,
          "percent_change": -0.16190152430739915
        },
        "VS. FORECAST": {
          "value": 890283,
          "percent_change": -1.3658578227372644
        },
        "VS. PRIOR YEAR": {
          "value": 793995,
          "percent_change": 10.595532717460438
        }
      },
      "entity_rollup": "sum"
    },
    {
      "row_type": "entity",
      "code": "PG:Developer Licenses|BU:Software Products",
      "name": "Developer Licenses",
      "id": 8,
      "level": 2,
      "parent_id": 3,
      "measures": "count",
      "columns": {
        "Actuals": {
          "value": 687739,
          "percent_change": null
        },
        "VS. AOP": {
          "value": 683471,
          "percent_change": 0.6244595600983802
        },
        "VS. FORECAST": {
          "value": 685227,
          "percent_change": 0.36659384408378537
        },
        "VS. PRIOR YEAR": {
          "value": 658579,
          "percent_change": 4.427714822367552
        }
      },
      "entity_rollup": "sum"
    },
    {
      "row_type": "entity",
      "code": "BU:Professional Services",
      "name": "Support",
      "id": 2,
      "level": 1,
      "parent_id": 0,
      "measures": "count",
      "columns": {
        "Actuals": {
          "value": 575337,
          "percent_change": null
        },
        "VS. AOP": {
          "value": 583857,
          "percent_change": -1.4592614287402565
        },
        "VS. FORECAST": {
          "value": 582310,
          "percent_change": -1.1974721368343322
        },
        "VS. PRIOR YEAR": {
          "value": 550811,
          "percent_change": 4.452707008393078
        }
      },
      "entity_rollup": "sum"
    },
    {
      "row_type": "entity",
      "code": "PG:Managed Support|BU:Professional Services",
      "name": "Managed Support",
      "id": 6,
      "level": 2,
      "parent_id": 2,
      "measures": "count",
      "columns": {
        "Actuals": {
          "value": 575337,
          "percent_change": null
        },
        "VS. AOP": {
          "value": 583857,
          "percent_change": -1.4592614287402565
        },
        "VS. FORECAST": {
          "value": 582310,
          "percent_change": -1.1974721368343322
        },
        "VS. PRIOR YEAR": {
          "value": 550811,
          "percent_change": 4.452707008393078
        }
      },
      "entity_rollup": "sum"
    },
    {
      "row_type": "entity",
      "code": "BU:Cloud Services",
      "name": "Cloud",
      "id": 1,
      "level": 1,
      "parent_id": 0,
      "measures": "count",
      "columns": {
        "Actuals": {
          "value": 3282343.0198,
          "percent_change": null
        },
        "VS. AOP": {
          "value": 3346013,
          "percent_change": -1.902861112613732
        },
        "VS. FORECAST": {
          "value": 3302703.4386,
          "percent_change": -0.6164773549462493
        },
        "VS. PRIOR YEAR": {
          "value": 3255562.8007,
          "percent_change": 0.8225987560197481
        }
      },
      "entity_rollup": "sum"
    },
    {
      "row_type": "entity",
      "code": "PG:Storage|BU:Cloud Services",
      "name": "Storage",
      "id": 5,
      "level": 2,
      "parent_id": 1,
      "measures": "count",
      "columns": {
        "Actuals": {
          "value": 490212.7348999999,
          "percent_change": null
        },
        "VS. AOP": {
          "value": 493821,
          "percent_change": -0.7306827980179209
        },
        "VS. FORECAST": {
          "value": 490999.39569999994,
          "percent_change": -0.1602162460665555
        },
        "VS. PRIOR YEAR": {
          "value": 479246.0979,
          "percent_change": 2.2883101287740146
        }
      },
      "entity_rollup": "sum"
    },
    {
      "row_type": "entity",
      "code": "PG:Compute|BU:Cloud Services",
      "name": "Compute",
      "id": 4,
      "level": 2,
      "parent_id": 1,
      "measures": "count",
      "columns": {
        "Actuals": {
          "value": 2792130.2849,
          "percent_change": null
        },
        "VS. AOP": {
          "value": 2852192,
          "percent_change": -2.1058089742906563
        },
        "VS. FORECAST": {
          "value": 2811704.0429000002,
          "percent_change": -0.6961528561097043
        },
        "VS. PRIOR YEAR": {
          "value": 2776316.7028,
          "percent_change": 0.5695885517690142
        }
      },
      "entity_rollup": "sum"
    }
  ]
}
```

## Key Features

### Automatic Hierarchy Traversal

The endpoint automatically:
1. Retrieves the entity hierarchy starting from `root_entity_code`
2. Excludes any entities in `exclude_entity_codes`
3. Identifies leaf entities (no children) and parent entities
4. Maintains proper parent-child relationships

### Formula-Based Calculation

For each leaf entity:
1. Aggregates facts for each line item in the formula
2. Evaluates the formula using Polars expressions
3. Returns calculated value for the entity

### Automatic Rollup

For parent entities:
1. Collects all descendant entity values
2. Applies `entity_rollup` aggregation (sum, avg, min, max)
3. Propagates values up the hierarchy

### Entity Line Item Overrides

Use `entity_line_item_overrides` to specify different line items for specific entities:
```json
"entity_line_item_overrides": {
  "MANUFACTURING": ["REVENUE", "COGS"],
  "SERVICES": ["REVENUE", "OPEX"]
}
```

## Error Handling

### Common Errors

| Error Type | HTTP Status | When It Occurs |
|------------|-------------|----------------|
| Tenant not found | 404 | Invalid `tenant_id` |
| No data for tenant | 404 | Tenant has no facts/dimensions |
| Root entity not found | 400 | `root_entity_code` doesn't exist |
| Invalid line item code | 400 | Line item in formula doesn't exist |
| Invalid formula | 400 | Malformed `entity_formula` |
| Too many line items | 400 | More than 20 line items |
| Too many comparison columns | 400 | More than 5 comparison columns |
| Division by zero | 500 | Formula results in division by zero |

### Error Response Format

```json
{
  "detail": "Root entity 'XYZ' not found in database"
}
```

## Performance Considerations

- **Initial generation**: ~2-4 seconds for large hierarchies
- **Cached retrieval**: ~200-500ms
- **Optimization**: Uses vectorized Polars operations
- **Recommendation**: Enable caching for static hierarchies

## Best Practices

1. **Use meaningful formulas** that match business logic
2. **Choose appropriate rollup** aggregation (sum for $ amounts, avg for %)
3. **Override line items** per entity for flexibility
4. **Exclude irrelevant entities** using `exclude_entity_codes`
