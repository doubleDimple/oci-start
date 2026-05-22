package com.doubledimple.ociserver.controller;

import com.doubledimple.ociserver.service.LogService;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.MediaType;
import org.springframework.stereotype.Controller;
import org.springframework.ui.Model;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.servlet.mvc.method.annotation.SseEmitter;

import java.io.IOException;
import java.util.List;

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
     * 新增：SSE 实时日志流接口
     */
    @GetMapping(value = "/streamLogs", produces = MediaType.TEXT_EVENT_STREAM_VALUE)
    public SseEmitter streamLogs(@RequestParam(value = "isBootLog", required = false, defaultValue = "false") boolean isBootLog) {
        return logService.streamLogs(isBootLog);
    }
}
