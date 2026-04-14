# Combined PnL Table Endpoint

Generate a single Profit & Loss table by combining multiple PnL requests (Line Item Hierarchy and/or Entity Hierarchy) executed concurrently and concatenated together.

## Endpoint
```
POST /fdm/read/pnl-table
```

## Overview

The Combined PnL endpoint allows you to:
- Execute multiple PnL table requests in parallel
- Combine Line Item Hierarchy and Entity Hierarchy tables
- Maintain hierarchical structure across concatenated tables
- Share column configurations across all sub-tables
- Generate complex multi-section P&L reports efficiently
- Cache the combined result for faster retrieval

This is the most flexible endpoint, allowing you to build comprehensive P&L reports with multiple sections (e.g., Revenue details, Entity breakdown, Custom calculations).

## Request Model

### `MainPnLRequest`

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `tenant_id` | `int` | Yes | Tenant ID to query |
| `table_label` | `str` | Yes | Display label for the combined table |
| `pnl_requests` | `List[LineItemHierarchyPnLRequest \| EntityHierarchyPnLRequest]` | Yes | List of PnL requests to combine (1-10) |
| `cache_table` | `bool` | No | Whether to cache results (default: `true`) |

### Sub-Request Models

See detailed documentation for:
- [`LineItemHierarchyPnLRequest`](./line_item_hierarchy_pnl.md#lineitemhierarchypnlrequest)
- [`EntityHierarchyPnLRequest`](./entity_hierarchy_pnl.md#entityhierarchypnlrequest)

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

### Example 1: Mighty Devs Totals PnL

Combines two entity hierarchy tables into one.

**Request:**
```json
{
    "tenant_id": 2,
    "table_label": "Totals PnL Table",
    "cache_table": false,
    "pnl_requests": [
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
        },
        {
            "tenant_id": 2,
            "table_label": "Overview PNL Revenue",
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
            "entity_formula": "{{net_revenue}}",
            "entity_rollup": "sum",
            "entity_rollup_measure": "USD",
            "line_items": [
                {
                "line_item_code": "net_revenue",
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
                    "name_override": "Net Revenue"
                }
            ]
        }
    ]
}
```

**Response:**
```json
{
  "table_label": "Totals PnL Table",
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
      "id": 1,
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
          "value": 5258947.8007,
          "percent_change": 3.129793740833324
        }
      },
      "entity_rollup": "sum"
    },
    {
      "row_type": "entity",
      "code": "BU:Software Products",
      "name": "Software",
      "id": 2,
      "level": 1,
      "parent_id": 1,
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
      "id": 3,
      "level": 2,
      "parent_id": 2,
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
      "id": 4,
      "level": 2,
      "parent_id": 2,
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
      "id": 5,
      "level": 1,
      "parent_id": 1,
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
      "parent_id": 5,
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
      "id": 7,
      "level": 1,
      "parent_id": 1,
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
          "value": 3255562.8006999996,
          "percent_change": 0.8225987560197625
        }
      },
      "entity_rollup": "sum"
    },
    {
      "row_type": "entity",
      "code": "PG:Storage|BU:Cloud Services",
      "name": "Storage",
      "id": 8,
      "level": 2,
      "parent_id": 7,
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
          "value": 479246.09789999994,
          "percent_change": 2.288310128774027
        }
      },
      "entity_rollup": "sum"
    },
    {
      "row_type": "entity",
      "code": "PG:Compute|BU:Cloud Services",
      "name": "Compute",
      "id": 9,
      "level": 2,
      "parent_id": 7,
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
    },
    {
      "row_type": "entity",
      "code": "ROOT:All",
      "name": "Net Revenue",
      "id": 1,
      "level": 0,
      "parent_id": null,
      "measures": "USD",
      "columns": {
        "Actuals": {
          "value": 755405387.5102,
          "percent_change": null
        },
        "VS. AOP": {
          "value": 756531953.4128001,
          "percent_change": -0.14891187312287146
        },
        "VS. FORECAST": {
          "value": 755360014.6605,
          "percent_change": 0.00600678468800961
        },
        "VS. PRIOR YEAR": {
          "value": 690997201.2936999,
          "percent_change": 9.321048782240183
        }
      },
      "entity_rollup": "sum"
    },
    {
      "row_type": "entity",
      "code": "BU:Software Products",
      "name": "Software Products",
      "id": 2,
      "level": 1,
      "parent_id": 1,
      "measures": "USD",
      "columns": {
        "Actuals": {
          "value": 368077414.86800003,
          "percent_change": null
        },
        "VS. AOP": {
          "value": 370763754.46099997,
          "percent_change": -0.724542127076369
        },
        "VS. FORECAST": {
          "value": 371123353.4134,
          "percent_change": -0.8207348088944019
        },
        "VS. PRIOR YEAR": {
          "value": 328264575.5662,
          "percent_change": 12.1282776958585
        }
      },
      "entity_rollup": "sum"
    },
    {
      "row_type": "entity",
      "code": "PG:Productivity Licenses|BU:Software Products",
      "name": "Productivity Licenses",
      "id": 3,
      "level": 2,
      "parent_id": 2,
      "measures": "USD",
      "columns": {
        "Actuals": {
          "value": 178057799.83990002,
          "percent_change": null
        },
        "VS. AOP": {
          "value": 179991527.8174,
          "percent_change": -1.0743438877088392
        },
        "VS. FORECAST": {
          "value": 181689549.8448,
          "percent_change": -1.9988766596660268
        },
        "VS. PRIOR YEAR": {
          "value": 154199026.85390002,
          "percent_change": 15.472713072700278
        }
      },
      "entity_rollup": "sum"
    },
    {
      "row_type": "entity",
      "code": "PG:Developer Licenses|BU:Software Products",
      "name": "Developer Licenses",
      "id": 4,
      "level": 2,
      "parent_id": 2,
      "measures": "USD",
      "columns": {
        "Actuals": {
          "value": 190019615.0281,
          "percent_change": null
        },
        "VS. AOP": {
          "value": 190772226.6436,
          "percent_change": -0.39450795786223103
        },
        "VS. FORECAST": {
          "value": 189433803.5686,
          "percent_change": 0.3092433601946201
        },
        "VS. PRIOR YEAR": {
          "value": 174065548.7123,
          "percent_change": 9.165550813371635
        }
      },
      "entity_rollup": "sum"
    },
    {
      "row_type": "entity",
      "code": "BU:Professional Services",
      "name": "Professional Services",
      "id": 5,
      "level": 1,
      "parent_id": 1,
      "measures": "USD",
      "columns": {
        "Actuals": {
          "value": 102189881.83650002,
          "percent_change": null
        },
        "VS. AOP": {
          "value": 103567223.91250001,
          "percent_change": -1.3299015112770174
        },
        "VS. FORECAST": {
          "value": 104421190.45830001,
          "percent_change": -2.1368350734241535
        },
        "VS. PRIOR YEAR": {
          "value": 97675858.0016,
          "percent_change": 4.6214324882880256
        }
      },
      "entity_rollup": "sum"
    },
    {
      "row_type": "entity",
      "code": "PG:Project Services|BU:Professional Services",
      "name": "Project Services",
      "id": 10,
      "level": 2,
      "parent_id": 5,
      "measures": "USD",
      "columns": {
        "Actuals": {
          "value": 27979976.240000002,
          "percent_change": null
        },
        "VS. AOP": {
          "value": 28514487.299999997,
          "percent_change": -1.874524533358855
        },
        "VS. FORECAST": {
          "value": 28292684.83,
          "percent_change": -1.1052630454795764
        },
        "VS. PRIOR YEAR": {
          "value": 31952941.18,
          "percent_change": -12.433800436770928
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
      "parent_id": 5,
      "measures": "USD",
      "columns": {
        "Actuals": {
          "value": 74209905.59650001,
          "percent_change": null
        },
        "VS. AOP": {
          "value": 75052736.6125,
          "percent_change": -1.122985055630356
        },
        "VS. FORECAST": {
          "value": 76128505.62830001,
          "percent_change": -2.520212390832458
        },
        "VS. PRIOR YEAR": {
          "value": 65722916.8216,
          "percent_change": 12.913286849299944
        }
      },
      "entity_rollup": "sum"
    },
    {
      "row_type": "entity",
      "code": "BU:Cloud Services",
      "name": "Cloud Services",
      "id": 7,
      "level": 1,
      "parent_id": 1,
      "measures": "USD",
      "columns": {
        "Actuals": {
          "value": 285138090.8057,
          "percent_change": null
        },
        "VS. AOP": {
          "value": 282200975.03929996,
          "percent_change": 1.040788667009747
        },
        "VS. FORECAST": {
          "value": 279815470.78880006,
          "percent_change": 1.9021893256636142
        },
        "VS. PRIOR YEAR": {
          "value": 265056767.7259,
          "percent_change": 7.5762348013563905
        }
      },
      "entity_rollup": "sum"
    },
    {
      "row_type": "entity",
      "code": "PG:Storage|BU:Cloud Services",
      "name": "Storage",
      "id": 8,
      "level": 2,
      "parent_id": 7,
      "measures": "USD",
      "columns": {
        "Actuals": {
          "value": 154621892.60689998,
          "percent_change": null
        },
        "VS. AOP": {
          "value": 150640829.51160002,
          "percent_change": 2.642751708289949
        },
        "VS. FORECAST": {
          "value": 150318244.3472,
          "percent_change": 2.8630245639109178
        },
        "VS. PRIOR YEAR": {
          "value": 140364845.4637,
          "percent_change": 10.157135211527747
        }
      },
      "entity_rollup": "sum"
    },
    {
      "row_type": "entity",
      "code": "PG:Compute|BU:Cloud Services",
      "name": "Compute",
      "id": 9,
      "level": 2,
      "parent_id": 7,
      "measures": "USD",
      "columns": {
        "Actuals": {
          "value": 130516198.19880001,
          "percent_change": null
        },
        "VS. AOP": {
          "value": 131560145.5277,
          "percent_change": -0.7935133582534624
        },
        "VS. FORECAST": {
          "value": 129497226.44160002,
          "percent_change": 0.7868676304503852
        },
        "VS. PRIOR YEAR": {
          "value": 124691922.2622,
          "percent_change": 4.670932832643985
        }
      },
      "entity_rollup": "sum"
    }
  ]
}
```

## Key Features

### Concurrent Execution

All PnL requests in `pnl_requests` are executed in parallel:
- Reduces total processing time
- Results are combined in order of requested after all complete

### Automatic Row ID Renumbering

The endpoint ensures no ID conflicts:
1. Builds global ID mapping across all tables
2. Renumbers row IDs sequentially (starting from 1)
3. Updates `parent_id` references to match new IDs
4. Preserves hierarchy relationships

### Column Consistency Validation

**CRITICAL**: All requests must have **identical column configurations**:
- Same `main_column.label` and `main_column.version_code`
- Same number of comparison columns
- Same `comparison_columns[i].label` and `version_code` for each position

If columns don't match, the request fails with validation error.

### Hierarchy Preservation

When concatenating tables:
- Each table's internal hierarchy is maintained
- Parent-child relationships are preserved
- Row levels reflect original hierarchy depth
- New root rows (from different requests) have `parent_id: null`

## Validation Rules

### Column Consistency Check

```python
# All requests must have matching columns
first_request = {
  "main_column": {"label": "Q1 2024", "version_code": "ACTUALS"},
  "comparison_columns": [
    {"label": "Q1 2023", "version_code": "ACTUALS"}
  ]
}

# This will FAIL - different main column label
second_request = {
  "main_column": {"label": "Q1 Budget", "version_code": "BUDGET"},
  "comparison_columns": [
    {"label": "Q1 2023", "version_code": "ACTUALS"}
  ]
}

# This will SUCCEED - same column config
second_request = {
  "main_column": {"label": "Q1 2024", "version_code": "ACTUALS"},
  "comparison_columns": [
    {"label": "Q1 2023", "version_code": "ACTUALS"}
  ]
}
```

### Request Count Limits

- No Current Limits
- Recommended: < 8, 8 default parallel workers to generate the tables

## Error Handling

### Common Errors

| Error Type | HTTP Status | When It Occurs |
|------------|-------------|----------------|
| Column mismatch | 400 | Inconsistent column configurations across requests |
| Too many requests | 400 | More than 10 PnL requests |
| Empty request list | 400 | No requests in `pnl_requests` |
| Tenant not found | 404 | Invalid `tenant_id` |
| Sub-request error | 400/500 | Error in one of the PnL requests |

### Error Response Format

```json
{
  "detail": "Column configuration mismatch: Request 2 has different main column label 'Q2 2024' vs 'Q1 2024'"
}
```

## Performance Considerations

- **Parallel execution**: N requests execute concurrently
- **Total time**: ~max(request_times) + concatenation overhead (~100-200ms)
- **Example**: 3 requests (2s, 1.5s, 3s) → ~3.2s total
- **Caching**: Combined table is cached, not individual requests
- **Memory**: All tables loaded in memory during concatenation

## Best Practices

1. **Match column configs** across all requests exactly
2. **Limit requests** to 3-5 for better readability
3. **Use logical sections** (Revenue, Costs, Regional breakdown)
4. **Disable individual caching** (`cache_table: false` on sub-requests)
5. **Enable combined caching** (`cache_table: true` on main request)
6. **Order requests** logically
7. **Use mixed request types** to leverage both hierarchies
