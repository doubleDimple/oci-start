package com.doubledimple.ociserver;

import java.io.BufferedReader;
import java.io.BufferedWriter;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.io.OutputStream;
import java.io.OutputStreamWriter;
import java.net.HttpURLConnection;
import java.net.URL;
import java.net.URLEncoder;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.util.Arrays;
import java.util.Date;
import java.util.HashMap;
import java.util.HashSet;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

public class FtlI18nExtractor {

    // FTL 文件目录
    private static final String FTL_DIR = "/Users/admin/IdeaProjects/openSouce/oci-start-pro/oci-server/src/main/resources/templates";

    // 生成的国际化文件路径
    private static final String ZH_FILE = "/Users/admin/IdeaProjects/openSouce/oci-start-pro/oci-server/src/main/resources/messages_zh_CN.properties";
    private static final String EN_FILE = "/Users/admin/IdeaProjects/openSouce/oci-start-pro/oci-server/src/main/resources/messages_zh_CN.properties";

    // 用于生成唯一key的计数器
    private static final Map<String, Integer> keyCounters = new HashMap<>();

    // 已处理的文本，避免重复
    private static final Set<String> processedTexts = new HashSet<>();

    public static void main(String[] args) throws IOException {
        System.out.println("🚀 开始提取FTL文件中的中文文本...\n");

        Map<String, String> zhMap = new LinkedHashMap<>();

        // 1. 扫描所有 FTL 文件
        System.out.println("📁 扫描目录: " + FTL_DIR);
        Files.walk(Paths.get(FTL_DIR))
                .filter(path -> path.toString().endsWith(".ftl"))
                .forEach(path -> {
                    try {
                        System.out.println("📄 处理文件: " + path.getFileName());
                        extractChinese(path, zhMap);
                    } catch (IOException e) {
                        System.err.println("❌ 处理文件失败: " + path + " - " + e.getMessage());
                    }
                });

        System.out.println("\n📊 提取统计:");
        System.out.println("   总共提取了 " + zhMap.size() + " 个中文文本");

        // 2. 写入中文 properties
        System.out.println("\n💾 生成中文资源文件...");
        writeProperties(ZH_FILE, zhMap, false);

        // 3. 调用翻译 API 生成英文
        System.out.println("\n🔄 开始翻译英文文本...");
        Map<String, String> enMap = new LinkedHashMap<>();

        int count = 0;
        int total = zhMap.size();

        for (Map.Entry<String, String> entry : zhMap.entrySet()) {
            count++;
            String key = entry.getKey();
            String chineseText = entry.getValue();

            System.out.printf("[%d/%d] 翻译: %s\n", count, total,
                    chineseText.length() > 30 ? chineseText.substring(0, 30) + "..." : chineseText);

            String englishText = translateToEnglish(chineseText);
            enMap.put(key, englishText);

            // 避免API限流，每5个请求暂停1秒
            if (count % 5 == 0) {
                try {
                    Thread.sleep(1000);
                } catch (InterruptedException e) {
                    Thread.currentThread().interrupt();
                    break;
                }
            }
        }

        // 4. 写入英文 properties
        System.out.println("\n💾 生成英文资源文件...");
        writeProperties(EN_FILE, enMap, true);

        System.out.println("\n✅ 国际化文件已生成: ");
        System.out.println(" - " + ZH_FILE);
        System.out.println(" - " + EN_FILE);

        // 生成使用说明
        generateUsageInstructions();
    }

    // 改进的中文提取方法
    private static void extractChinese(Path path, Map<String, String> zhMap) throws IOException {
        List<String> lines = Files.readAllLines(path, StandardCharsets.UTF_8);
        String fileName = path.getFileName().toString().replace(".ftl", "");

        // 多种匹配模式
        List<Pattern> patterns = Arrays.asList(
                // HTML标签内的文本: >中文文本<
                Pattern.compile(">(\\s*[^<]*?[\\u4e00-\\u9fff][^<]*?\\s*)<"),

                // 属性值: title="中文" placeholder="中文" alt="中文"
                Pattern.compile("(?:title|placeholder|alt|value|aria-label)\\s*=\\s*[\"']([^\"']*[\\u4e00-\\u9fff][^\"']*)[\"']", Pattern.CASE_INSENSITIVE),

                // JavaScript/FTL字符串: "中文" '中文'
                Pattern.compile("[\"']([^\"']*[\\u4e00-\\u9fff][^\"']*)[\"']"),

                // 按钮和常见标签文本
                Pattern.compile("<(?:button|span|label|strong|b|em|i|h[1-6]|p|div|td|th)[^>]*>\\s*([^<]*[\\u4e00-\\u9fff][^<]*?)\\s*</(?:button|span|label|strong|b|em|i|h[1-6]|p|div|td|th)>", Pattern.CASE_INSENSITIVE),

                // 注释中的中文（说明性文本）
                Pattern.compile("<!--\\s*([^>]*[\\u4e00-\\u9fff][^>]*)\\s*-->"),

                // FTL注释
                Pattern.compile("<#--\\s*([^>]*[\\u4e00-\\u9fff][^>]*)\\s*-->")
        );

        String content = String.join("\n", lines);

        for (Pattern pattern : patterns) {
            Matcher matcher = pattern.matcher(content);
            while (matcher.find()) {
                String text = matcher.group(1).trim();
                if (isValidChineseText(text) && !processedTexts.contains(text)) {
                    processedTexts.add(text);
                    String key = generateBetterKey(text, fileName);
                    zhMap.putIfAbsent(key, text);
                }
            }
        }
    }

    // 判断是否为有效的中文文本
    private static boolean isValidChineseText(String text) {
        if (text == null || text.trim().isEmpty()) {
            return false;
        }

        String cleaned = text.replaceAll("\\s+", " ").trim();

        // 过滤条件
        if (cleaned.length() < 2 ||                           // 太短
                cleaned.matches("^[\\d\\s\\p{Punct}]+$") ||       // 纯数字和标点
                cleaned.matches("^[a-zA-Z\\s\\p{Punct}]+$") ||    // 纯英文
                !Pattern.compile("[\\u4e00-\\u9fff]").matcher(cleaned).find()) { // 不包含中文
            return false;
        }

        // 排除常见的非文本内容
        String[] excludePatterns = {
                "^\\s*$", "^[\\s\\p{Punct}]+$", "^\\d+$",
                ".*\\$\\{.*\\}.*", ".*#\\{.*\\}.*",  // FTL表达式
                ".*javascript:.*", ".*onclick.*",     // JS代码
                ".*@.*\\..*"                          // 邮箱等
        };

        for (String pattern : excludePatterns) {
            if (cleaned.matches(pattern)) {
                return false;
            }
        }

        return true;
    }

    // 改进的key生成方法
    private static String generateBetterKey(String text, String fileName) {
        // 预定义的常见词汇映射
        Map<String, String> commonMappings = new HashMap<>();
        commonMappings.put("确定", "confirm");
        commonMappings.put("取消", "cancel");
        commonMappings.put("保存", "save");
        commonMappings.put("删除", "delete");
        commonMappings.put("编辑", "edit");
        commonMappings.put("添加", "add");
        commonMappings.put("新增", "add");
        commonMappings.put("搜索", "search");
        commonMappings.put("查询", "search");
        commonMappings.put("操作", "operations");
        commonMappings.put("管理", "management");
        commonMappings.put("设置", "settings");
        commonMappings.put("配置", "config");
        commonMappings.put("用户", "user");
        commonMappings.put("系统", "system");
        commonMappings.put("服务", "service");
        commonMappings.put("状态", "status");
        commonMappings.put("成功", "success");
        commonMappings.put("失败", "failed");
        commonMappings.put("错误", "error");
        commonMappings.put("警告", "warning");
        commonMappings.put("信息", "info");
        commonMappings.put("区域", "region");
        commonMappings.put("租户", "tenant");
        commonMappings.put("实例", "instance");
        commonMappings.put("监控", "monitor");
        commonMappings.put("日志", "log");
        commonMappings.put("安全", "security");
        commonMappings.put("规则", "rule");
        commonMappings.put("代理", "proxy");
        commonMappings.put("备份", "backup");
        commonMappings.put("导入", "import");
        commonMappings.put("导出", "export");
        commonMappings.put("文件", "file");
        commonMappings.put("登录", "login");
        commonMappings.put("退出", "logout");
        commonMappings.put("关于", "about");
        commonMappings.put("版本", "version");
        commonMappings.put("更新", "update");
        commonMappings.put("同步", "sync");
        commonMappings.put("列表", "list");
        commonMappings.put("详情", "detail");

        // 文件名前缀映射
        String filePrefix = getFilePrefix(fileName);

        // 尝试匹配常见词汇
        for (Map.Entry<String, String> entry : commonMappings.entrySet()) {
            if (text.contains(entry.getKey())) {
                String baseKey = filePrefix + "." + entry.getValue();
                return ensureUniqueKey(baseKey);
            }
        }

        // 生成描述性key
        String descriptiveKey = generateDescriptiveKey(text);
        String baseKey = filePrefix + "." + descriptiveKey;

        return ensureUniqueKey(baseKey);
    }

    private static String getFilePrefix(String fileName) {
        // 文件名到前缀的映射
        Map<String, String> filePrefixMap = new HashMap<>();
        filePrefixMap.put("tenant_region_list", "tenant");
        filePrefixMap.put("tenant_speed_add", "tenant");
        filePrefixMap.put("header", "common");
        filePrefixMap.put("sidebar", "menu");
        filePrefixMap.put("version_info", "version");
        filePrefixMap.put("pagination", "page");

        return filePrefixMap.getOrDefault(fileName, fileName.toLowerCase().replaceAll("[^a-z0-9]", ""));
    }

    private static String generateDescriptiveKey(String text) {
        // 简化文本生成key
        String simplified = text.replaceAll("[\\s\\p{Punct}]+", " ").trim();

        if (simplified.length() <= 4) {
            // 短文本直接使用
            return "short_" + Math.abs(simplified.hashCode()) % 1000;
        } else if (simplified.length() <= 8) {
            // 中等长度文本
            return "medium_" + Math.abs(simplified.hashCode()) % 1000;
        } else {
            // 长文本
            return "long_" + Math.abs(simplified.hashCode()) % 1000;
        }
    }

    private static String ensureUniqueKey(String baseKey) {
        String uniqueKey = baseKey;
        int counter = keyCounters.getOrDefault(baseKey, 0);

        if (counter > 0) {
            uniqueKey = baseKey + "_" + counter;
        }

        keyCounters.put(baseKey, counter + 1);
        return uniqueKey;
    }

    // 改进的Properties文件写入方法
    private static void writeProperties(String filePath, Map<String, String> map, boolean isEnglish) throws IOException {
        // 确保目录存在
        Path file = Paths.get(filePath);
        Files.createDirectories(file.getParent());

        try (OutputStreamWriter writer = new OutputStreamWriter(
                Files.newOutputStream(file), StandardCharsets.UTF_8);
             BufferedWriter bufferedWriter = new BufferedWriter(writer)) {

            // 写入文件头
            bufferedWriter.write("# " + (isEnglish ? "English" : "Chinese") + " Messages\n");
            bufferedWriter.write("# Generated automatically at: " + new Date() + "\n");
            bufferedWriter.write("# Total entries: " + map.size() + "\n");
            bufferedWriter.write("# File encoding: UTF-8\n\n");

            if (isEnglish) {
                bufferedWriter.write("# Note: Some translations may need manual review\n");
                bufferedWriter.write("# 注意：部分翻译可能需要人工校对\n\n");
            }

            // 按key排序写入
            map.entrySet().stream()
                    .sorted(Map.Entry.comparingByKey())
                    .forEach(entry -> {
                        try {
                            String key = entry.getKey();
                            String value = entry.getValue();

                            // 转义特殊字符
                            String escapedValue = escapeProperties(value);
                            bufferedWriter.write(key + "=" + escapedValue + "\n");

                        } catch (IOException e) {
                            throw new RuntimeException(e);
                        }
                    });
        }

        System.out.println("✅ 已生成: " + filePath + " (共 " + map.size() + " 条)");
    }

    private static String escapeProperties(String text) {
        if (text == null) return "";

        return text.replace("\\", "\\\\")
                .replace("\n", "\\n")
                .replace("\r", "\\r")
                .replace("\t", "\\t")
                .replace("=", "\\=")
                .replace(":", "\\:")
                .replace("#", "\\#")
                .replace("!", "\\!");
    }

    // 翻译方法（您的原始实现，已修复）
    private static String translateToEnglish(String chinese) {
        if (chinese == null || chinese.trim().isEmpty()) {
            return chinese;
        }

        try {
            String cleanText = cleanText(chinese);
            if (cleanText.isEmpty()) {
                return chinese;
            }

            String translated = callGoogleTranslate(cleanText, "zh", "en");
            return translated != null ? translated : "[TODO] " + chinese;

        } catch (Exception e) {
            System.err.println("⚠️ 翻译失败: " + chinese + " - " + e.getMessage());
            return "[TODO] " + chinese;
        }
    }

    private static String callGoogleTranslate(String text, String from, String to) throws Exception {
        String encodedText = URLEncoder.encode(text, "UTF-8");
        String urlStr = String.format(
                "https://translate.googleapis.com/translate_a/single?client=gtx&sl=%s&tl=%s&dt=t&q=%s",
                from, to, encodedText
        );

        String response = sendHttpRequest(urlStr, "GET", null);
        return parseGoogleResponse(response);
    }

    private static String cleanText(String text) {
        if (text == null) return "";

        return text.replaceAll("<[^>]+>", "")
                .replaceAll("\\s+", " ")
                .trim();
    }

    private static String sendHttpRequest(String urlStr, String method, String postData) throws Exception {
        URL url = new URL(urlStr);
        HttpURLConnection conn = (HttpURLConnection) url.openConnection();

        conn.setRequestMethod(method);
        conn.setRequestProperty("User-Agent",
                "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36");
        conn.setConnectTimeout(10000);
        conn.setReadTimeout(15000);

        if ("POST".equals(method) && postData != null) {
            conn.setDoOutput(true);
            conn.setRequestProperty("Content-Type", "application/json; charset=UTF-8");
            try (OutputStream os = conn.getOutputStream()) {
                os.write(postData.getBytes("UTF-8"));
                os.flush();
            }
        }

        int responseCode = conn.getResponseCode();
        InputStream inputStream = responseCode >= 200 && responseCode < 300 ?
                conn.getInputStream() : conn.getErrorStream();

        try (BufferedReader reader = new BufferedReader(
                new InputStreamReader(inputStream, "UTF-8"))) {
            StringBuilder response = new StringBuilder();
            String line;
            while ((line = reader.readLine()) != null) {
                response.append(line);
            }
            return response.toString();
        }
    }

    private static String parseGoogleResponse(String response) {
        if (response == null || response.isEmpty()) {
            return null;
        }

        try {
            Pattern pattern = Pattern.compile("\\[\\[\\[\"([^\"]+)\"");
            Matcher matcher = pattern.matcher(response);

            if (matcher.find()) {
                String result = matcher.group(1);
                return result.replace("\\n", "\n")
                        .replace("\\t", "\t")
                        .replace("\\\"", "\"")
                        .replace("\\/", "/");
            }

            if (response.startsWith("[[[\"")) {
                int start = 4;
                int end = response.indexOf("\"", start);
                if (end > start) {
                    return response.substring(start, end);
                }
            }

        } catch (Exception e) {
            System.err.println("解析翻译响应失败: " + e.getMessage());
        }

        return null;
    }

    // 生成使用说明
    private static void generateUsageInstructions() {
        System.out.println("\n📋 使用说明:");
        System.out.println("1. 检查生成的properties文件内容是否正确");
        System.out.println("2. 校对英文翻译，修改不准确的翻译");
        System.out.println("3. 在FTL文件中使用 ${msg('key')} 替换硬编码中文");
        System.out.println("4. 配置Spring Boot国际化支持");

        System.out.println("\n🔧 Spring配置示例:");
        System.out.println("@Bean");
        System.out.println("public MessageSource messageSource() {");
        System.out.println("    ResourceBundleMessageSource source = new ResourceBundleMessageSource();");
        System.out.println("    source.setBasename(\"messages\");");
        System.out.println("    source.setDefaultEncoding(\"UTF-8\");");
        System.out.println("    return source;");
        System.out.println("}");

        System.out.println("\n📝 FTL使用示例:");
        System.out.println("原来: <h1>区域管理</h1>");
        System.out.println("替换: <h1>${msg('tenant.region.management')}</h1>");

        System.out.println("\n🌐 语言切换:");
        System.out.println("中文: ?lang=zh_CN");
        System.out.println("英文: ?lang=en_US");
    }
}
