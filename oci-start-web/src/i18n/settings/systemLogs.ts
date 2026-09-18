import openLogs from '../boot/logs'

export default {
  zh: {
    ...openLogs.zh,
    title: '系统日志', logArea: '系统日志内容', empty: '暂无已读取的系统日志，新日志到达后会显示在这里。',
    search: '搜索当前已加载的日志…', clearSearch: '清除搜索', matched: '匹配 {matched} / 已加载 {total} 条',
    noMatches: '当前已加载的日志没有匹配结果', searchScope: '仅搜索当前页面保留的日志，最多最近 1000 条。',
    wrap: '自动换行', latest: '回到最新', newEntries: '{count} 条新日志', lineNumber: '当前会话序号 {number}',
    following: '跟随输出', reading: '已暂停跟随，可自由浏览', followHint: '向上滚动会暂停跟随；点击“回到最新”恢复。',
    historyLoaded: '历史已读取', historyPending: '历史尚未读取',
  },
  en: {
    ...openLogs.en,
    title: 'System logs', logArea: 'System log contents', empty: 'No system logs have been loaded. New entries will appear here as they arrive.',
    search: 'Search loaded logs…', clearSearch: 'Clear search', matched: '{matched} matches / {total} loaded',
    noMatches: 'No matches in the loaded logs', searchScope: 'Searches only entries retained on this page, up to the most recent 1000.',
    wrap: 'Wrap lines', latest: 'Jump to latest', newEntries: '{count} new entries', lineNumber: 'Session entry {number}',
    following: 'Following output', reading: 'Following paused; browse freely', followHint: 'Scrolling up pauses following. Use “Jump to latest” to resume.',
    historyLoaded: 'History loaded', historyPending: 'History not loaded',
  },
}
