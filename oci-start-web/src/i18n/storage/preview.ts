const zh = {
  title: '对象预览', bucket: '存储桶：{name}', close: '关闭', download: '下载', retry: '重新读取',
  loading: '正在读取预览…', textLimit: '文本预览最多 {limit}，按纯文本显示。更大的文件请下载后查看。',
  mediaLimit: '图片和 PDF 预览最多 {limit}。更大的文件请下载后查看。',
  tooLarge: '文件超过当前类型的预览上限 {limit}，请下载后查看。',
  unsupported: '此文件类型不支持在线预览，请下载后查看。', missingTarget: '尚未选择要预览的对象。',
  invalidPdf: '返回内容不是可识别的 PDF，无法显示预览。请重新读取或下载后核对文件。',
  imageFailed: '浏览器无法显示这张图片，请重新读取或下载后查看。', emptyText: '这是一个空文本文件。',
  pdfLabel: 'PDF 预览：{name}', pdfFallback: '如果浏览器无法显示 PDF，请下载后查看。',
  errors: {
    invalidResponse: '返回内容不完整或格式不正确，无法显示预览。', invalidInput: '对象信息无效，请重新选择对象。',
    invalidUrl: '下载地址无效，请重新选择对象。', requestFailed: '预览读取失败，请重试或下载后查看。',
    timeout: '预览读取超时，请重试或下载后查看。', cancelled: '预览读取已取消。', previewTooLarge: '文件超过预览上限，请下载后查看。',
  },
}

const en = {
  title: 'Object preview', bucket: 'Bucket: {name}', close: 'Close', download: 'Download', retry: 'Reload',
  loading: 'Loading preview…', textLimit: 'Text previews are limited to {limit} and displayed as plain text. Download larger files to view them.',
  mediaLimit: 'Image and PDF previews are limited to {limit}. Download larger files to view them.',
  tooLarge: 'This file exceeds the {limit} preview limit for its type. Download it to view it.',
  unsupported: 'This file type does not support an online preview. Download it to view it.', missingTarget: 'Select an object to preview.',
  invalidPdf: 'The response is not a recognizable PDF. Reload the preview or download and check the file.',
  imageFailed: 'The browser could not display this image. Reload the preview or download the file.', emptyText: 'This text file is empty.',
  pdfLabel: 'PDF preview: {name}', pdfFallback: 'If your browser cannot display the PDF, download it to view it.',
  errors: {
    invalidResponse: 'The response is incomplete or has an invalid format. The preview cannot be displayed.', invalidInput: 'The object information is invalid. Select the object again.',
    invalidUrl: 'The download URL is invalid. Select the object again.', requestFailed: 'The preview could not be loaded. Retry or download the file.',
    timeout: 'Loading the preview timed out. Retry or download the file.', cancelled: 'Loading the preview was cancelled.', previewTooLarge: 'The file exceeds the preview limit. Download it to view it.',
  },
}

export default { zh, en }
