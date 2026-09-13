export default {
  zh: {
    titles: { proxy: '为连接，多一份从容。', traffic: '让每一份流量，都心中有数。', import: '把你的租户，带到这里。', export: '一份备份，一份安心。', batchCheck: '所有账号，一目了然。', transfer: '记录这一次转让。' },
    labels: { proxy: '快速配置代理', traffic: '流量预警', import: '导入租户数据', export: '安全导出', batchCheck: '批量检测账号', transfer: '租户转让' },
    actions: { reload: '重新加载', createAndBind: '新建并绑定', saveBinding: '保存绑定', import: '确认导入', verifyDownload: '验证并下载', sendCode: '发送验证码', confirmTransfer: '确认转让', save: '保存设置', confirm: '确认', cancel: '取消', close: '关闭', resend: '重新发送', startCheck: '开始检测' },
    proxy: {
      mode: '代理配置方式', selectExisting: '选择已有代理', globalPool: '使用全局代理池', globalPoolHint: '解除专属代理绑定，恢复全局共享',
      forced: '强制代理', optional: '非强制代理', available: '通畅', unavailable: '不通', empty: '还没有专属代理。你可以新建一个，并立即绑定。',
      customName: '自定义名称', namePlaceholder: '便于识别，可选', type: '代理类型', http: 'HTTP', https: 'HTTPS', policy: '连接策略', host: '代理地址', hostPlaceholder: '127.0.0.1', port: '端口', portPlaceholder: '8080',
      username: '用户名', password: '密码', optionalPlaceholder: '可选', createHint: '创建后自动绑定当前租户。其它租户可在代理配置中共用此代理。',
    },
    traffic: {
      statistics: '流量统计与预警', statisticsHint: '按月统计租户流量，达到阈值时提醒你。', enableStatistics: '启用流量统计与预警', threshold: '每月预警阈值（GB）', thresholdPlaceholder: '输入大于 0 的数值', thresholdHint: '保存配置时必须填写有效阈值。',
      autoShutdown: '达到阈值后自动关机', autoShutdownHint: '启用后，达到阈值将关闭租户实例。', confirmTitle: '启用自动关机', confirmMessage: '月流量达到 {threshold} GB 后，将自动关闭该租户的实例。确认保存？',
    },
    import: { fileLabel: '选择租户数据 JSON 文件', reading: '正在读取文件…', selectFile: '选择或拖入 JSON 文件', ready: '{count} 条租户记录，已准备好导入', fileHint: '使用从 oci-start 导出的租户数据文件', replaceFile: '重新选择文件', browse: '浏览文件', hint: '导入会恢复文件中的租户与区域数据，已有的租户记录会跳过。', success: '租户数据已导入' },
    export: { singleScope: '导出当前租户及其区域数据', allScope: '导出全部 OCI 租户数据', scopeHint: '通过通知终端验证码验证后，下载 JSON 备份。', codeLabel: '通知终端验证码', codePlaceholder: '输入 6 位验证码', codeHint: '验证码已发送，请在有效期内完成导出。', hint: '点击下方按钮，将验证码发送到你已配置的通知终端。', codeSent: '验证码已发送至你的通知终端', success: '导出文件已准备好' },
    check: {
      idle: '逐个检查 OCI 账号，实时查看检测结果。', connecting: '正在连接检测服务…', checking: '正在检测账号…', progress: '已检测 {processed} 个账号', progressWithTotal: '已检测 {processed} / {total} 个账号', complete: '检测完成，共 {total} 个账号', interrupted: '检测中断',
      introTitle: '一轮检测，掌握整体状态。', intro: '检查全部 OCI 主账号，不受当前搜索条件影响。检测结束后会更新异常账号状态，并发送检测通知。', total: '账号总数', active: '正常账号', inactive: '异常账号', unresolved: '另有 {count} 个账号未返回确定状态，请结合检测日志查看。', logs: '账号检测日志', waiting: '等待服务端返回检测进度…', closeHint: '关闭窗口将断开实时进度，服务端可能仍在完成当前检测。',
    },
    transfer: { hint: '输入租户转让金额。保存后，该租户的操作功能将被锁定。', amount: '转让金额', amountPlaceholder: '0.00', confirmMessage: '保存转让后，该租户的操作功能将被锁定。确认继续？' },
    saved: '已保存',
    errors: { default: '操作未完成，请稍后重试', loadConfiguration: '未能读取配置，请重试后保存', missingTenant: '未找到租户，请关闭后重新打开', invalidImport: '请选择导出的租户 JSON 文件，内容应为非空数据数组', invalidJson: '文件不是有效的 JSON，请检查后重新选择', readFile: '文件读取失败', sendCode: '验证码发送失败', proxyHost: '请填写代理地址', proxyPort: '代理端口应为 1–65535 之间的整数', threshold: '请设置大于 0 的流量预警阈值', exportFormat: '导出响应格式有误，请重新获取验证码后重试', checkFormat: '检测结果格式有误', checkResult: '无法读取检测结果', stream: '检测连接已中断，已保留收到的日志' },
  },
  en: {
    titles: { proxy: 'Connect with confidence.', traffic: 'Keep track of your traffic.', import: 'Bring your tenants here.', export: 'Keep a backup handy.', batchCheck: 'All accounts at a glance.', transfer: 'Record this transfer.' },
    labels: { proxy: 'Configure proxy', traffic: 'Traffic alerts', import: 'Import tenant data', export: 'Secure export', batchCheck: 'Check accounts', transfer: 'Transfer tenant' },
    actions: { reload: 'Reload', createAndBind: 'Create and bind', saveBinding: 'Save binding', import: 'Import data', verifyDownload: 'Verify and download', sendCode: 'Send code', confirmTransfer: 'Confirm transfer', save: 'Save settings', confirm: 'Confirm', cancel: 'Cancel', close: 'Close', resend: 'Resend', startCheck: 'Start check' },
    proxy: {
      mode: 'Proxy configuration mode', selectExisting: 'Use existing proxy', globalPool: 'Use the global proxy pool', globalPoolHint: 'Remove the dedicated binding and use the shared pool',
      forced: 'Required proxy', optional: 'Optional proxy', available: 'Available', unavailable: 'Unavailable', empty: 'No dedicated proxies yet. Create one to bind it now.',
      customName: 'Custom name', namePlaceholder: 'A helpful name, optional', type: 'Proxy type', http: 'HTTP', https: 'HTTPS', policy: 'Connection policy', host: 'Proxy host', hostPlaceholder: '127.0.0.1', port: 'Port', portPlaceholder: '8080',
      username: 'Username', password: 'Password', optionalPlaceholder: 'Optional', createHint: 'The new proxy will be bound to this tenant. Other tenants can share it through proxy settings.',
    },
    traffic: {
      statistics: 'Traffic monitoring and alerts', statisticsHint: 'Track monthly traffic and get notified at the threshold.', enableStatistics: 'Enable traffic monitoring and alerts', threshold: 'Monthly alert threshold (GB)', thresholdPlaceholder: 'Enter a value above 0', thresholdHint: 'A valid threshold is required to save these settings.',
      autoShutdown: 'Shut down at the threshold', autoShutdownHint: 'Turn off this tenant’s instances when traffic reaches the threshold.', confirmTitle: 'Enable automatic shutdown', confirmMessage: 'This tenant’s instances will shut down when monthly traffic reaches {threshold} GB. Save these settings?',
    },
    import: { fileLabel: 'Choose a tenant data JSON file', reading: 'Reading file…', selectFile: 'Choose or drop a JSON file', ready: '{count} tenant records ready to import', fileHint: 'Use a tenant data file exported from oci-start', replaceFile: 'Choose another file', browse: 'Browse files', hint: 'Import restores the tenant and region data in the file. Existing tenant records are skipped.', success: 'Tenant data imported' },
    export: { singleScope: 'Export this tenant and its regions', allScope: 'Export all OCI tenant data', scopeHint: 'Verify with a code from your notification channel to download a JSON backup.', codeLabel: 'Verification code', codePlaceholder: 'Enter the 6-digit code', codeHint: 'Code sent. Complete the export before it expires.', hint: 'Send a verification code to your configured notification channel to continue.', codeSent: 'Code sent to your notification channel', success: 'Your export is ready' },
    check: {
      idle: 'Check OCI accounts one by one and follow the results live.', connecting: 'Connecting to the check service…', checking: 'Checking accounts…', progress: '{processed} accounts checked', progressWithTotal: '{processed} / {total} accounts checked', complete: 'Check complete: {total} accounts', interrupted: 'Check interrupted',
      introTitle: 'Check your account status.', intro: 'Check all primary OCI accounts, regardless of the current search. The service updates inactive accounts and sends a notification when finished.', total: 'Total accounts', active: 'Active accounts', inactive: 'Inactive accounts', unresolved: '{count} accounts have no confirmed status. See the check log for details.', logs: 'Account check log', waiting: 'Waiting for check progress…', closeHint: 'Closing this window disconnects live progress. The server may still be finishing the check.',
    },
    transfer: { hint: 'Enter the transfer amount. Tenant operations will be locked after saving.', amount: 'Transfer amount', amountPlaceholder: '0.00', confirmMessage: 'Tenant operations will be locked after this transfer is saved. Continue?' },
    saved: 'Saved',
    errors: { default: 'Unable to complete the operation. Please try again.', loadConfiguration: 'Could not load settings. Reload before saving.', missingTenant: 'Tenant not found. Close this dialog and reopen it.', invalidImport: 'Choose an exported tenant JSON file containing a non-empty array of records.', invalidJson: 'This file is not valid JSON. Check it and choose another file.', readFile: 'Could not read the file', sendCode: 'Could not send the verification code', proxyHost: 'Enter the proxy host', proxyPort: 'Enter a whole-number port from 1 to 65535', threshold: 'Enter a traffic threshold above 0', exportFormat: 'The export response is invalid. Request a new code and try again.', checkFormat: 'Invalid check result format', checkResult: 'Could not read the check results', stream: 'The check connection was lost. Received logs have been kept.' },
  },
}
