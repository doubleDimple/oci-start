package com.doubledimple.ocicommon.utils;

import com.doubledimple.ocicommon.param.PingResult;

import java.util.ArrayList;
import java.util.List;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

/**
 * @version 1.0.0
 * @ClassName PingResultParser
 * @Description TODO
 * @Author doubleDimple
 * @Date 2025-03-04 17:31
 */
public class PingResultParser {


        /**
         * 解析ping测试输出并提取失败的IP地址
         * @param pingOutput ping命令的完整输出结果
         * @return 失败的IP地址列表
         */
        public static List<String> getFailedIPs(String pingOutput) {
            List<String> failedIPs = new ArrayList<>();

            // 使用正则表达式匹配失败的IP记录
            // 寻找包含"✗ 失败: xxx.xxx.xxx.xxx 不可达"的行
            Pattern failurePattern = Pattern.compile("✗ 失败: (\\d+\\.\\d+\\.\\d+\\.\\d+) 不可达");
            Matcher failureMatcher = failurePattern.matcher(pingOutput);

            while (failureMatcher.find()) {
                String failedIP = failureMatcher.group(1);
                failedIPs.add(failedIP);
            }

            // 如果使用上面的模式没有找到失败IP，可能是因为使用了不同的输出格式
            // 尝试查找包含"packet loss"且不是0%的记录
            if (failedIPs.isEmpty()) {
                Pattern ipPattern = Pattern.compile("正在ping (\\d+\\.\\d+\\.\\d+\\.\\d+)\\.\\.\\.");
                Pattern lossPattern = Pattern.compile("(\\d+)% packet loss");

                String[] sections = pingOutput.split("----------------------------------------");

                for (String section : sections) {
                    Matcher ipMatcher = ipPattern.matcher(section);
                    if (ipMatcher.find()) {
                        String ip = ipMatcher.group(1);

                        Matcher lossMatcher = lossPattern.matcher(section);
                        if (lossMatcher.find()) {
                            int lossPercentage = Integer.parseInt(lossMatcher.group(1));
                            if (lossPercentage == 100) {
                                // 100%丢包率表示ping失败
                                failedIPs.add(ip);
                            }
                        } else if (!section.contains("received")) {
                            // 如果没有找到包含"received"的行，可能是因为ping命令没有成功执行
                            failedIPs.add(ip);
                        }
                    }
                }
            }

            return failedIPs;
        }

        /**
         * 解析ping测试输出并提取成功的IP地址
         * @param pingOutput ping命令的完整输出结果
         * @return 成功的IP地址列表
         */
        public static List<String> getSuccessfulIPs(String pingOutput) {
            List<String> successfulIPs = new ArrayList<>();

            // 使用正则表达式匹配成功的IP记录
            // 寻找包含"✓ 成功: xxx.xxx.xxx.xxx 可达"的行
            Pattern successPattern = Pattern.compile("✓ 成功: (\\d+\\.\\d+\\.\\d+\\.\\d+) 可达");
            Matcher successMatcher = successPattern.matcher(pingOutput);

            while (successMatcher.find()) {
                String successIP = successMatcher.group(1);
                successfulIPs.add(successIP);
            }

            return successfulIPs;
        }

        /**
         * 获取所有被ping的IP地址
         * @param pingOutput ping命令的完整输出结果
         * @return 所有IP地址列表
         */
        public static List<String> getAllPingedIPs(String pingOutput) {
            List<String> allIPs = new ArrayList<>();

            // 使用正则表达式匹配所有被ping的IP
            Pattern ipPattern = Pattern.compile("正在ping (\\d+\\.\\d+\\.\\d+\\.\\d+)\\.\\.\\.");
            Matcher ipMatcher = ipPattern.matcher(pingOutput);

            while (ipMatcher.find()) {
                String ip = ipMatcher.group(1);
                allIPs.add(ip);
            }

            return allIPs;
        }

        /**
         * 解析ping测试输出并获取每个IP的详细信息
         * @param pingOutput ping命令的完整输出结果
         * @return IP及其ping状态的详细信息
         */
        public static List<PingResult> getPingResults(String pingOutput) {
            List<PingResult> results = new ArrayList<>();

            // 将输出分割为各个IP的部分
            String[] sections = pingOutput.split("----------------------------------------");

            for (String section : sections) {
                // 跳过空部分或只包含标题的部分
                if (section.trim().isEmpty() || section.trim().equals("开始执行ping测试...") ||
                        section.trim().equals("ping测试完成！")) {
                    continue;
                }

                // 提取IP地址
                Pattern ipPattern = Pattern.compile("正在ping (\\d+\\.\\d+\\.\\d+\\.\\d+)\\.\\.\\.");
                Matcher ipMatcher = ipPattern.matcher(section);

                if (ipMatcher.find()) {
                    String ip = ipMatcher.group(1);
                    boolean isReachable = section.contains("✓ 成功");

                    // 提取ping统计信息
                    String statistics = "";
                    Pattern statsPattern = Pattern.compile("--- .* ping statistics ---[\\s\\S]*");
                    Matcher statsMatcher = statsPattern.matcher(section);
                    if (statsMatcher.find()) {
                        statistics = statsMatcher.group(0);
                    }

                    // 创建结果对象
                    PingResult result = new PingResult(ip, isReachable, statistics);
                    results.add(result);
                }
            }

            return results;
        }
}
