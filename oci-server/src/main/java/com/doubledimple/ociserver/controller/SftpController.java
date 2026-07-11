package com.doubledimple.ociserver.controller;

import com.doubledimple.ocicommon.param.ApiResponse;
import com.jcraft.jsch.ChannelSftp;
import com.jcraft.jsch.JSch;
import com.jcraft.jsch.Session;
import lombok.extern.slf4j.Slf4j;
import org.springframework.http.MediaType;
import org.springframework.stereotype.Controller;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.multipart.MultipartFile;

import javax.servlet.http.HttpServletResponse;
import java.io.IOException;
import java.net.URLEncoder;
import java.util.Map;
import java.util.Properties;

@Slf4j
@Controller
@RequestMapping("/oci/sftp")
public class SftpController extends BaseController {

    @PostMapping("/upload")
    @ResponseBody
    public ApiResponse upload(
            @RequestParam("host") String host,
            @RequestParam("port") int port,
            @RequestParam("username") String username,
            @RequestParam("password") String password,
            @RequestParam("remotePath") String remotePath,
            @RequestParam("file") MultipartFile file) {

        if (file.isEmpty()) {
            return ApiResponse.error("文件不能为空");
        }

        Session session = null;
        ChannelSftp channel = null;
        try {
            session = createSession(host, port, username, password);
            channel = (ChannelSftp) session.openChannel("sftp");
            channel.connect(5000);

            String remoteFilePath = remotePath.endsWith("/")
                    ? remotePath + file.getOriginalFilename()
                    : remotePath;

            channel.put(file.getInputStream(), remoteFilePath);
            return ApiResponse.success("上传成功: " + remoteFilePath);
        } catch (Exception e) {
            log.warn("SFTP upload failed: {}", e.getMessage());
            return ApiResponse.error("上传失败: " + e.getMessage());
        } finally {
            disconnectSilently(channel, session);
        }
    }

    @PostMapping(value = "/download", produces = MediaType.APPLICATION_OCTET_STREAM_VALUE)
    public void download(@RequestBody Map<String, Object> req, HttpServletResponse response) throws IOException {
        String host = (String) req.get("host");
        int port = req.get("port") instanceof Integer ? (Integer) req.get("port") : Integer.parseInt(req.get("port").toString());
        String username = (String) req.get("username");
        String password = (String) req.get("password");
        String remotePath = (String) req.get("remotePath");

        Session session = null;
        ChannelSftp channel = null;
        try {
            session = createSession(host, port, username, password);
            channel = (ChannelSftp) session.openChannel("sftp");
            channel.connect(5000);

            String filename = remotePath.contains("/")
                    ? remotePath.substring(remotePath.lastIndexOf('/') + 1)
                    : remotePath;

            String encodedName = URLEncoder.encode(filename, "UTF-8").replace("+", "%20");
            response.setContentType("application/octet-stream");
            response.setHeader("Content-Disposition", "attachment; filename*=UTF-8''" + encodedName);

            channel.get(remotePath, response.getOutputStream());
            response.getOutputStream().flush();
        } catch (Exception e) {
            log.warn("SFTP download failed: {}", e.getMessage());
            response.sendError(HttpServletResponse.SC_INTERNAL_SERVER_ERROR, "下载失败: " + e.getMessage());
        } finally {
            disconnectSilently(channel, session);
        }
    }

    private Session createSession(String host, int port, String username, String password) throws Exception {
        JSch jsch = new JSch();
        Session session = jsch.getSession(username, host, port);
        session.setPassword(password);
        Properties config = new Properties();
        config.put("StrictHostKeyChecking", "no");
        session.setConfig(config);
        session.connect(15000);
        return session;
    }

    private void disconnectSilently(ChannelSftp channel, Session session) {
        try { if (channel != null) channel.disconnect(); } catch (Exception ignored) {}
        try { if (session != null) session.disconnect(); } catch (Exception ignored) {}
    }
}
