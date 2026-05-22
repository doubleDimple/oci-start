package com.doubledimple.ocicommon.utils;

import java.io.ByteArrayInputStream;
import java.io.ByteArrayOutputStream;
import java.nio.charset.StandardCharsets;
import java.util.zip.GZIPInputStream;
import java.util.zip.GZIPOutputStream;

/**
 * @version 1.0.0
 * @ClassName ZipUtils
 * @Description TODO
 * @Author doubleDimple
 * @Date 2025-12-07 11:50
 */
public class ZipUtils {

    public static byte[] gzip(String text) throws Exception {
        ByteArrayOutputStream bos = new ByteArrayOutputStream();
        try (GZIPOutputStream gzip = new GZIPOutputStream(bos)) {
            gzip.write(text.getBytes(StandardCharsets.UTF_8));
        }
        return bos.toByteArray();
    }

    public static String ungzip(byte[] compressed) throws Exception {
        ByteArrayOutputStream bos = new ByteArrayOutputStream();
        try (GZIPInputStream gis = new GZIPInputStream(new ByteArrayInputStream(compressed))) {
            byte[] buffer = new byte[4096];
            int len;
            while ((len = gis.read(buffer)) != -1) {
                bos.write(buffer, 0, len);
            }
        }
        return new String(bos.toByteArray(), StandardCharsets.UTF_8);
    }

}
