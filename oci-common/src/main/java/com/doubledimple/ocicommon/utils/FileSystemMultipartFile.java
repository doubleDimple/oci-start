package com.doubledimple.ocicommon.utils;

import org.springframework.web.multipart.MultipartFile;

import java.io.File;
import java.io.FileInputStream;
import java.io.IOException;
import java.io.InputStream;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;

/**
 * @version 1.0.0
 * @ClassName FileSystemMultipartFile
 * @Description TODO
 * @Author doubleDimple
 * @Date 2025-07-11 23:40
 */
public class FileSystemMultipartFile implements MultipartFile {
    private final String name;
    private final String originalFilename;
    private final String contentType;
    private final File file;

    public FileSystemMultipartFile(String filePath) throws IOException {
        this(filePath, "file");
    }

    public FileSystemMultipartFile(String filePath, String paramName) throws IOException {
        Path path = Paths.get(filePath).toAbsolutePath().normalize(); // 添加normalize()
        this.file = path.toFile();

        // 调试输出
        System.out.println("原始路径: " + filePath);
        System.out.println("清理后路径: " + path);

        this.name = paramName;
        this.originalFilename = path.getFileName().toString();
        String detectedContentType = Files.probeContentType(path);
        this.contentType = detectedContentType != null ? detectedContentType : "application/octet-stream";
    }

    @Override
    public String getName() {
        return name;
    }

    @Override
    public String getOriginalFilename() {
        return originalFilename;
    }

    @Override
    public String getContentType() {
        return contentType;
    }

    @Override
    public boolean isEmpty() {
        boolean b = file.length() == 0 || !file.exists();
        return b;
    }

    @Override
    public long getSize() {
        return file.length();
    }

    @Override
    public byte[] getBytes() throws IOException {
        return Files.readAllBytes(file.toPath());
    }

    @Override
    public InputStream getInputStream() throws IOException {
        return new FileInputStream(file);
    }

    @Override
    public void transferTo(File dest) throws IOException, IllegalStateException {
        Files.copy(file.toPath(), dest.toPath());
    }
}
