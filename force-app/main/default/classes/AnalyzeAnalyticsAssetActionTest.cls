@isTest
private class AnalyzeAnalyticsAssetActionTest {
    // A minimal Dashboard Results API payload exercising: title, ordered
    // components (row/column), a single-grouping report, and a metric-only report.
    private static String samplePayload() {
        return JSON.serialize(
            new Map<String, Object>{
                'attributes' => new Map<String, Object>{ 'dashboardName' => 'Sales Rep Simple Dashboard' },
                'dashboardMetadata' => new Map<String, Object>{
                    'components' => new List<Object>{
                        new Map<String, Object>{ 'id' => 'C1', 'header' => 'My Pipeline', 'type' => 'Report' },
                        new Map<String, Object>{ 'id' => 'C2', 'header' => 'My Closed Business', 'type' => 'Report' }
                    },
                    'layout' => new Map<String, Object>{
                        'components' => new List<Object>{
                            new Map<String, Object>{ 'row' => 0, 'column' => 1 },
                            new Map<String, Object>{ 'row' => 0, 'column' => 0 }
                        }
                    }
                },
                'componentData' => new List<Object>{
                    // C1: single-level grouping (My Pipeline by stage)
                    new Map<String, Object>{
                        'componentId' => 'C1',
                        'reportResult' => new Map<String, Object>{
                            'groupingsDown' => new Map<String, Object>{
                                'groupings' => new List<Object>{
                                    new Map<String, Object>{ 'key' => '0', 'label' => 'Qualification' },
                                    new Map<String, Object>{ 'key' => '1', 'label' => 'Negotiation' }
                                }
                            },
                            'groupingsAcross' => new Map<String, Object>{ 'groupings' => new List<Object>{} },
                            'factMap' => new Map<String, Object>{
                                '0!T' => new Map<String, Object>{
                                    'aggregates' => new List<Object>{ new Map<String, Object>{ 'value' => 2700000 } }
                                },
                                '1!T' => new Map<String, Object>{
                                    'aggregates' => new List<Object>{ new Map<String, Object>{ 'value' => 1900000 } }
                                },
                                'T!T' => new Map<String, Object>{
                                    'aggregates' => new List<Object>{ new Map<String, Object>{ 'value' => 4600000 } }
                                }
                            }
                        }
                    },
                    // C2: metric-only (no groupings)
                    new Map<String, Object>{
                        'componentId' => 'C2',
                        'reportResult' => new Map<String, Object>{
                            'groupingsDown' => new Map<String, Object>{ 'groupings' => new List<Object>{} },
                            'groupingsAcross' => new Map<String, Object>{ 'groupings' => new List<Object>{} },
                            'factMap' => new Map<String, Object>{
                                'T!T' => new Map<String, Object>{
                                    'aggregates' => new List<Object>{ new Map<String, Object>{ 'value' => 10000000 } }
                                }
                            }
                        }
                    }
                }
            }
        );
    }

    @isTest
    static void rawPayloadProducesOrderedMarkdown() {
        AnalyzeAnalyticsAssetAction.Request req = new AnalyzeAnalyticsAssetAction.Request();
        req.rawPayloadJson = samplePayload();

        Test.startTest();
        List<AnalyzeAnalyticsAssetAction.Response> out = AnalyzeAnalyticsAssetAction.analyze(
            new List<AnalyzeAnalyticsAssetAction.Request>{ req }
        );
        Test.stopTest();

        System.assertEquals(1, out.size());
        AnalyzeAnalyticsAssetAction.Response res = out[0];
        System.assert(res.success, 'should succeed: ' + res.errorMessage);
        System.assertEquals('Sales Rep Simple Dashboard', res.dashboardTitle);

        String md = res.normalizedDataText;
        System.assert(md.contains('# Dashboard: Sales Rep Simple Dashboard'), md);
        System.assert(md.contains('## My Pipeline'), md);
        System.assert(md.contains('Qualification'), md);
        System.assert(md.contains('## My Closed Business'), md);

        // Layout ordering: C2 is row0/col0, C1 is row0/col1 → Closed Business first.
        Integer posClosed = md.indexOf('My Closed Business');
        Integer posPipeline = md.indexOf('My Pipeline');
        System.assert(posClosed < posPipeline, 'components should be in screen order (row/column): ' + md);
    }

    @isTest
    static void blankInputReturnsError() {
        AnalyzeAnalyticsAssetAction.Request req = new AnalyzeAnalyticsAssetAction.Request();
        // no rawPayloadJson, no dashboardIdOrUrl
        List<AnalyzeAnalyticsAssetAction.Response> out = AnalyzeAnalyticsAssetAction.analyze(
            new List<AnalyzeAnalyticsAssetAction.Request>{ req }
        );
        System.assertEquals(1, out.size());
        System.assertEquals(false, out[0].success);
        System.assert(out[0].errorMessage != null, 'should report an error');
    }

    @isTest
    static void nullRequestsReturnsEmpty() {
        List<AnalyzeAnalyticsAssetAction.Response> out = AnalyzeAnalyticsAssetAction.analyze(null);
        System.assertEquals(0, out.size());
    }

    @isTest
    static void richTextComponentRendersHeading() {
        Map<String, Object> payload = new Map<String, Object>{
            'attributes' => new Map<String, Object>{ 'dashboardName' => 'RT Dash' },
            'dashboardMetadata' => new Map<String, Object>{
                'components' => new List<Object>{
                    new Map<String, Object>{
                        'id' => 'R1',
                        'type' => 'Dashboard',
                        'properties' => new Map<String, Object>{
                            'visualizationType' => 'RichText',
                            'content' => new Map<String, Object>{
                                'richTextContent' => JSON.serialize(
                                    new List<Object>{
                                        new Map<String, Object>{ 'insert' => 'Review HQ deal and proposal status\n' }
                                    }
                                )
                            }
                        }
                    }
                },
                'layout' => new Map<String, Object>{
                    'components' => new List<Object>{ new Map<String, Object>{ 'row' => 0, 'column' => 0 } }
                }
            },
            'componentData' => new List<Object>{}
        };

        AnalyzeAnalyticsAssetAction.Request req = new AnalyzeAnalyticsAssetAction.Request();
        req.rawPayloadJson = JSON.serialize(payload);

        List<AnalyzeAnalyticsAssetAction.Response> out = AnalyzeAnalyticsAssetAction.analyze(
            new List<AnalyzeAnalyticsAssetAction.Request>{ req }
        );
        System.assert(out[0].success, out[0].errorMessage);
        System.assert(out[0].normalizedDataText.contains('## Review HQ deal and proposal status'), out[0].normalizedDataText);
    }
}
