package com.doubledimple.ociserver.controller;

import cn.hutool.json.JSONUtil;
import com.doubledimple.ociserver.config.datamigration.DatabaseExportService;
import com.doubledimple.ociserver.config.datamigration.DatabaseImportService;
import com.doubledimple.ociserver.pojo.response.InstanceDetailsRes;
import lombok.extern.slf4j.Slf4j;
import org.springframework.data.domain.Page;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.stereotype.Controller;
import org.springframework.ui.Model;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.multipart.MultipartFile;

import javax.annotation.Resource;
import javax.servlet.http.HttpServletRequest;
import javax.servlet.http.HttpServletResponse;
import java.io.ByteArrayOutputStream;
import java.net.URLEncoder;
import java.nio.charset.StandardCharsets;

import static com.doubledimple.ociserver.utils.DesktopUtils.isMobileRequest;


@Controller
@RequestMapping("/migration")
@Slf4j
public class MigrationController extends BaseController{

    @Resource
    private DatabaseExportService databaseExportService;

    @Resource
    private DatabaseImportService databaseImportService;

    @GetMapping("/migPage")
    public String listUsers(HttpServletRequest request,
                            Model model) {
        model.addAttribute("activePage", "api-migPage");

        return "migration";

    }


    /**
     * 导出数据库 —— 客户端直接下载 SQL 文件
     */
    @GetMapping("/export")
    public ResponseEntity<byte[]> exportDatabase() {
        try {
            ByteArrayOutputStream baos = databaseExportService.exportDatabaseToStream();

            String fileName = "oci-start_backup_" + System.currentTimeMillis() + ".sql";
            fileName = URLEncoder.encode(fileName, "UTF-8");

            return ResponseEntity.ok()
                    .header(HttpHeaders.CONTENT_DISPOSITION, "attachment; filename=\"" + fileName + "\"")
                    .contentType(MediaType.APPLICATION_OCTET_STREAM)
                    .body(baos.toByteArray());

        } catch (Exception e) {
            log.error("数据库导出失败: {}", e.getMessage(), e);
            return ResponseEntity.badRequest()
                    .body(("导出失败: " + e.getMessage()).getBytes(StandardCharsets.UTF_8));
        }
    }

    /**
     * 导出加密备份 —— 下载加密的 .enc 文件，并在响应头返回 master-key
     */
    @GetMapping("/exportEncrypted")
    public void exportEncrypted(HttpServletResponse response) {
        try {
            databaseExportService.exportEncryptedBackup(response);

        } catch (Exception e) {
            log.error("加密备份导出失败: {}", e.getMessage(), e);

            try {
                response.setStatus(HttpServletResponse.SC_INTERNAL_SERVER_ERROR);
                response.setContentType("text/plain;charset=UTF-8");
                response.getWriter().write("导出加密备份失败: " + e.getMessage());
            } catch (Exception ignored) {}
        }
    }


    /**
     * 导入数据库 —— 上传 SQL 文件，自动导入
     */
    @PostMapping("/import")
    public ResponseEntity<String> importDatabase(@RequestParam("file") MultipartFile file) {
        if (file.isEmpty()) {
            return ResponseEntity.badRequest().body("请选择一个  文件");
        }

        try {
            // SQL 内容读取为字符串数组，每行一个字符串
            byte[] bytes = file.getBytes();
            String tempPath = System.getProperty("java.io.tmpdir") + "/import_" + System.currentTimeMillis() + ".sql";

            java.nio.file.Files.write(java.nio.file.Paths.get(tempPath), bytes);

            log.info("上传的 SQL 已保存到: {}", tempPath);

            databaseImportService.importFromFile(tempPath, null);

            return ResponseEntity.ok("导入成功");

        } catch (Exception e) {
            log.error("数据库导入失败: {}", e.getMessage(), e);
            return ResponseEntity.badRequest().body("数据导入失败");
        }
    }

    /**
     * 导入数据库（支持：明文 SQL + 加密 .enc）
     */
    @PostMapping("/importEncrypted")
    public ResponseEntity<String> importEncrypted(
            @RequestParam("file") MultipartFile file,
            @RequestParam(value = "masterKey", required = false) String masterKey) {

        if (file.isEmpty()) {
            return ResponseEntity.badRequest().body("请选择一个备份文件上传");
        }

        try {
            // 读取上传文件为字符串
            String content = new String(file.getBytes(), StandardCharsets.UTF_8).trim();

            // 调用新版导入逻辑
            databaseImportService.importAuto(content, masterKey);

            return ResponseEntity.ok("导入成功");

        } catch (Exception e) {
            log.error("备份导入失败: {}", e.getMessage(), e);
            return ResponseEntity.badRequest().body(""+ e.getMessage());
        }
    }
}
