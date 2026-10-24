const zh = {
  title: '费用统计', query: '查询费用', cancelQuery: '取消查询', back: '返回', backToTenants: '返回租户列表',
  timeRange: '时间范围', today: '今天', month: '本月', custom: '自定义', startDate: '开始日期', endDate: '结束日期',
  startPlaceholder: '选择开始日期', endPlaceholder: '选择结束日期', tenant: '租户 #{id}',
  dailyUsd: 'USD · 按日统计（UTC）', selectedRange: '{start} 至 {end}',
  queryHint: '选择时间范围后查询费用。', loading: '正在查询费用…', cancelled: '查询已取消。',
  categories: { total: '总费用', compute: '计算', storage: '存储', network: '网络', other: '其他' },
  trend: '每日费用趋势', trendAria: '所选时间范围内的每日费用趋势，具体记录可在下方费用明细表查看。',
  trendLegend: '显示的费用分类', trendToggle: '显示或隐藏{category}费用', noSeries: '选择至少一个费用分类查看趋势。',
  chartUnavailable: '暂时无法显示趋势图，可在下方明细表查看费用。',
  details: '费用明细', positiveOnly: '仅显示费用大于 0 的记录', allCosts: '显示全部费用',
  filterHint: '此筛选仅影响明细表，汇总与趋势仍包含完整查询结果。',
  count: '共 {count} 条记录', filteredCount: '显示 {count} 条，共 {total} 条记录',
  noPositive: '当前结果中没有费用大于 0 的记录。',
  noRecords: '未返回费用记录',
  noRecordsHint: '当前未返回费用明细，暂时无法确认费用金额。可稍后重新查询，或在云端账单中核对。',
  columns: { day: '日期', resourceType: '资源类型', sku: '产品 / SKU', resourceId: '资源 ID', cost: '费用（USD）' },
  resourceTypes: {
    instance: '计算实例', 'boot-volume': '引导卷', 'block-volume': '块存储卷', vnic: '虚拟网卡',
    vcn: '虚拟云网络', 'load-balancer': '负载均衡器', monitoring: '监控', other: '其他', unknown: '未知',
  },
  errors: {
    invalidTenant: '缺少有效的租户信息，请从租户列表打开费用统计。',
    invalidDate: '请选择有效的开始和结束日期。', reversedDates: '结束日期不能早于开始日期。',
    invalidResponse: '费用响应格式异常，无法确认金额，请重新查询。',
    requestFailed: '费用查询失败，请重试。', timeout: '费用查询超时，请重试。',
  },
}

const en = {
  title: 'Cost statistics', query: 'Query costs', cancelQuery: 'Cancel query', back: 'Back', backToTenants: 'Back to tenants',
  timeRange: 'Time range', today: 'Today', month: 'This month', custom: 'Custom', startDate: 'Start date', endDate: 'End date',
  startPlaceholder: 'Select a start date', endPlaceholder: 'Select an end date', tenant: 'Tenant #{id}',
  dailyUsd: 'USD · Daily (UTC)', selectedRange: '{start} to {end}',
  queryHint: 'Select a time range, then query costs.', loading: 'Querying costs…', cancelled: 'Query cancelled.',
  categories: { total: 'Total cost', compute: 'Compute', storage: 'Storage', network: 'Network', other: 'Other' },
  trend: 'Daily cost trend', trendAria: 'Daily costs for the selected time range. Individual records are available in the cost details table below.',
  trendLegend: 'Visible cost categories', trendToggle: 'Show or hide {category} costs', noSeries: 'Select at least one cost category to view its trend.',
  chartUnavailable: 'The trend chart is unavailable. You can still view costs in the details table below.',
  details: 'Cost details', positiveOnly: 'Show only costs greater than 0', allCosts: 'Show all costs',
  filterHint: 'This filter applies only to the details table. Totals and trends include the full query result.',
  count: '{count} records', filteredCount: 'Showing {count} of {total} records',
  noPositive: 'No records in this result have a cost greater than 0.',
  noRecords: 'No cost records returned',
  noRecordsHint: 'No cost details were returned, so the amount cannot be confirmed. Try again later or check the cloud billing console.',
  columns: { day: 'Date', resourceType: 'Resource type', sku: 'Product / SKU', resourceId: 'Resource ID', cost: 'Cost (USD)' },
  resourceTypes: {
    instance: 'Compute instance', 'boot-volume': 'Boot volume', 'block-volume': 'Block volume', vnic: 'Virtual NIC',
    vcn: 'Virtual cloud network', 'load-balancer': 'Load balancer', monitoring: 'Monitoring', other: 'Other', unknown: 'Unknown',
  },
  errors: {
    invalidTenant: 'A valid tenant is required. Open cost statistics from the tenant list.',
    invalidDate: 'Select valid start and end dates.', reversedDates: 'The end date must be on or after the start date.',
    invalidResponse: 'The cost response was invalid. Amounts could not be confirmed. Query again.',
    requestFailed: 'Cost query failed. Try again.', timeout: 'Cost query timed out. Try again.',
  },
}

export default { zh, en }
