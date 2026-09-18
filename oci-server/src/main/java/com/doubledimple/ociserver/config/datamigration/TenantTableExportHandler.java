package com.doubledimple.ociserver.config.datamigration;

import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;
import org.springframework.transaction.support.TransactionSynchronization;
import org.springframework.transaction.support.TransactionSynchronizationManager;

import java.io.ByteArrayOutputStream;
import java.io.InputStream;
import java.nio.ByteBuffer;
import java.nio.channels.SeekableByteChannel;
import java.nio.charset.CodingErrorAction;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.LinkOption;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.nio.file.StandardOpenOption;
import java.nio.file.attribute.BasicFileAttributes;
import java.nio.file.attribute.PosixFilePermissions;
import java.sql.ResultSet;
import java.util.EnumSet;
import java.util.Map;
import java.util.Objects;
import java.util.UUID;

/** Tenant key contents are validated before writes and restored only inside the import transaction. */
@Slf4j
@Component
public class TenantTableExportHandler implements TableExportHandler {
    public static final int MAX_KEY_BYTES = 1024 * 1024;
    private static final String COL_KEY_FILE = "KEY_FILE";
    private static final String COL_KEY_FILE_CONTENT = "KEY_FILE_CONTENT";

    @Value("${baseFile.filePath}")
    private String baseFile;

    @Override public String getTableName() { return "TENANT"; }
    @Override public void addExtraColumns(Map<String, String> columnMap) { columnMap.put(COL_KEY_FILE_CONTENT, "TEXT"); }

    @Override
    public Object handleExportValue(String columnName, ResultSet rows) throws Exception {
        if (!COL_KEY_FILE_CONTENT.equalsIgnoreCase(columnName)) return null;
        String reference = rows.getString(COL_KEY_FILE);
        if (reference == null || reference.trim().isEmpty()) return null;
        try {
            Path file = Paths.get(reference);
            BasicFileAttributes before = Files.readAttributes(file, BasicFileAttributes.class, LinkOption.NOFOLLOW_LINKS);
            if (!before.isRegularFile() || before.size() > MAX_KEY_BYTES) throw new IllegalStateException();
            ByteArrayOutputStream contents = new ByteArrayOutputStream();
            try (InputStream input = Files.newInputStream(file, StandardOpenOption.READ, LinkOption.NOFOLLOW_LINKS)) {
                byte[] buffer = new byte[4096];
                int count;
                while ((count = input.read(buffer)) != -1) {
                    if (contents.size() + count > MAX_KEY_BYTES) throw new IllegalStateException();
                    contents.write(buffer, 0, count);
                }
            }
            BasicFileAttributes after = Files.readAttributes(file, BasicFileAttributes.class, LinkOption.NOFOLLOW_LINKS);
            if (!after.isRegularFile() || before.size() != after.size() || !before.lastModifiedTime().equals(after.lastModifiedTime())
                    || !Objects.equals(before.fileKey(), after.fileKey())) throw new IllegalStateException();
            String content = StandardCharsets.UTF_8.newDecoder().onMalformedInput(CodingErrorAction.REPORT)
                    .onUnmappableCharacter(CodingErrorAction.REPORT).decode(ByteBuffer.wrap(contents.toByteArray())).toString();
            if (content.trim().isEmpty()) throw new IllegalStateException();
            return content;
        } catch (Exception failure) {
            throw new IllegalStateException("租户密钥文件缺失、不可读取、内容变化或超出限制，备份未生成");
        }
    }

    /** Pure validation: the importer calls this during its all-row preflight, before any DB or file write. */
    public void validateImportValue(Map<String, Object> rowData) {
        Object reference = rowData.get(COL_KEY_FILE);
        Object raw = rowData.get(COL_KEY_FILE_CONTENT);
        if (reference != null && !(reference instanceof String) || raw != null && !(raw instanceof String)) {
            throw new IllegalArgumentException("租户密钥字段无效");
        }
        String content = raw == null ? "" : (String) raw;
        if (content.length() > MAX_KEY_BYTES || content.getBytes(StandardCharsets.UTF_8).length > MAX_KEY_BYTES) {
            throw new IllegalArgumentException("租户密钥内容超过限制");
        }
        if (content.trim().isEmpty() && reference != null && !((String) reference).trim().isEmpty()) {
            throw new IllegalArgumentException("租户只有原机器密钥路径而无密钥内容，不能恢复");
        }
    }

    @Override
    public void handleImportValue(Map<String, Object> rowData, String ignoredKeyDir) throws Exception {
        validateImportValue(rowData);
        String content = (String) rowData.get(COL_KEY_FILE_CONTENT);
        rowData.remove(COL_KEY_FILE_CONTENT);
        if (content == null || content.trim().isEmpty()) return;
        if (!TransactionSynchronizationManager.isActualTransactionActive()
                || !TransactionSynchronizationManager.isSynchronizationActive()) {
            throw new IllegalStateException("恢复租户密钥需要有效导入事务");
        }
        Path created = null;
        Object ownedFileKey = null;
        try {
            if (baseFile == null || baseFile.trim().isEmpty()) throw new IllegalStateException();
            Path directory = Paths.get(baseFile).toAbsolutePath().normalize();
            // Only the local configured directory is used, never a path from the backup or a request parameter.
            Files.createDirectories(directory, PosixFilePermissions.asFileAttribute(PosixFilePermissions.fromString("rwx------")));
            directory = directory.toRealPath();
            if (!Files.isDirectory(directory) || !Files.getFileStore(directory).supportsFileAttributeView("posix")) {
                throw new IllegalStateException();
            }
            Path candidate = directory.resolve(UUID.randomUUID() + "_key.pem");
            try (SeekableByteChannel channel = Files.newByteChannel(candidate,
                    EnumSet.of(StandardOpenOption.CREATE_NEW, StandardOpenOption.WRITE),
                    PosixFilePermissions.asFileAttribute(PosixFilePermissions.fromString("rw-------")))) {
                created = candidate;
                ownedFileKey = Files.readAttributes(candidate, BasicFileAttributes.class, LinkOption.NOFOLLOW_LINKS).fileKey();
                final Path owned = created;
                final Object identity = ownedFileKey;
                TransactionSynchronizationManager.registerSynchronization(new TransactionSynchronization() {
                    @Override public void afterCompletion(int status) {
                        if (status == STATUS_ROLLED_BACK) deleteOwnedFile(owned, identity);
                        else if (status == STATUS_UNKNOWN) log.warn("导入事务结果未知，保留本次密钥文件待核对");
                    }
                });
                ByteBuffer bytes = ByteBuffer.wrap(content.getBytes(StandardCharsets.UTF_8));
                while (bytes.hasRemaining()) channel.write(bytes);
            }
            rowData.put(COL_KEY_FILE, candidate.toString());
        } catch (Exception failure) {
            if (created != null) deleteOwnedFile(created, ownedFileKey);
            throw new IllegalStateException("租户密钥恢复失败，请确认目录权限与文件系统支持");
        }
    }

    private static void deleteOwnedFile(Path file, Object identity) {
        try {
            if (!Files.exists(file, LinkOption.NOFOLLOW_LINKS)) return;
            BasicFileAttributes attributes = Files.readAttributes(file, BasicFileAttributes.class, LinkOption.NOFOLLOW_LINKS);
            if (!attributes.isRegularFile() || !Objects.equals(identity, attributes.fileKey())) {
                log.warn("本次导入密钥文件状态已变化，未自动删除");
                return;
            }
            Files.delete(file);
        } catch (Exception failure) {
            log.warn("本次导入的密钥文件清理未确认完成");
        }
    }
}
