package com.doubledimple.ocicommon.utils;

import lombok.extern.slf4j.Slf4j;
import org.springframework.web.multipart.MultipartFile;

import java.io.File;
import java.io.FileInputStream;
import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;

/**
 * @author doubleDimple
 * @date 2024:10:19日 13:34
 */
@Slf4j
public class FileUtils {


    public static void checkFile(String folderPath){
        // 转换为 Path 对象
        Path path = Paths.get(folderPath);
        // 检查文件夹是否存在，不存在则创建
        if (!Files.exists(path)) {
            try {
                // 创建文件夹
                Files.createDirectories(path);
                log.info("start create file:{}",folderPath);
            } catch (IOException e) {
                e.printStackTrace();
            }
        }
    }


    public static void deleteFile(String filePath){
        try {
            // 创建 Path 对象
            Path path = Paths.get(filePath);

            // 检查文件是否存在
            if (Files.exists(path)) {
                // 删除文件
                Files.delete(path);
            } else {
                log.warn("文件不存在");
            }
        } catch (IOException e) {
            log.error("文件删除失败,原因为:{}",e.getMessage());
        }
    }
}
