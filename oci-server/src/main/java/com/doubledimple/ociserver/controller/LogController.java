package com.doubledimple.ociserver.controller;

import com.doubledimple.ociserver.service.LogService;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.stereotype.Controller;
import org.springframework.ui.Model;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.ResponseBody;
import org.springframework.web.servlet.mvc.method.annotation.SseEmitter;

import java.util.HashMap;
import java.util.List;
import java.util.Map;

/**
 * @author doubleDimple
 * @date 2024:10:25日 21:57
 */
@Controller
@RequestMapping("/system")
public class LogController  extends BaseController{

    @Autowired
    private LogService logService;

    @GetMapping("/logs")
    public String showLogs(@RequestParam(value = "isBootLog", required = false, defaultValue = "false") boolean isBootLog,
                           Model model) {
        try {
            List<String> logLines = logService.getLatestLogLines(300, isBootLog);
            model.addAttribute("logLines", logLines);
        } catch (Exception e) {
            model.addAttribute("error", "无法读取日志文件");
        }
        model.addAttribute("activePage", "api-logs");
        return "sys_log";
    }

    @GetMapping("/openLogs")
    public String openLogs(Model model) {
        try {
            List<String> logLines = logService.getLatestLogLines(300, true);
            model.addAttribute("logLines", logLines);
        } catch (Exception e) {
            model.addAttribute("error", "无法读取日志文件");
        }
        model.addAttribute("activePage", "api-openLog");
        return "open_boot_log";
    }

    /**
     * 开机日志历史行 JSON（Mac 客户端 / AJAX，对齐 /boot/fullBootList/json 形态）
     */
    @GetMapping("/openLogs/json")
    @ResponseBody
    public ResponseEntity<Map<String, Object>> openLogsJson(
            @RequestParam(value = "lines", required = false, defaultValue = "300") int lines) {
        if (lines <= 0) {
            lines = 300;
        }
        if (lines > 1000) {
            lines = 1000;
        }
        Map<String, Object> result = new HashMap<>();
        try {
            List<String> logLines = logService.getLatestLogLines(lines, true);
            result.put("lines", logLines);
            result.put("count", logLines.size());
        } catch (Exception e) {
            result.put("lines", java.util.Collections.emptyList());
            result.put("count", 0);
            result.put("error", "无法读取日志文件");
        }
        return ResponseEntity.ok(result);
    }

    /**
     * 新增：SSE 实时日志流接口
     */
    @GetMapping(value = "/streamLogs", produces = MediaType.TEXT_EVENT_STREAM_VALUE)
    public SseEmitter streamLogs(@RequestParam(value = "isBootLog", required = false, defaultValue = "false") boolean isBootLog) {
        return logService.streamLogs(isBootLog);
    }
}
