package com.doubledimple.ociserver.service.permissions;

import cn.hutool.core.util.IdUtil;
import com.alibaba.fastjson2.JSON;
import com.doubledimple.dao.entity.Tenant;
import com.doubledimple.dao.repository.TenantRepository;
import com.doubledimple.ocicommon.enums.RegionEnum;
import com.doubledimple.ociai.utils.OciAiClientManager;
import com.doubledimple.ociserver.config.TenantProxyBinder;
import com.doubledimple.ociserver.utils.oracle.OciUtils;
import com.oracle.bmc.Region;
import com.oracle.bmc.auth.SimpleAuthenticationDetailsProvider;
import com.oracle.bmc.identity.model.RegionSubscription;
import org.bouncycastle.asn1.pkcs.PrivateKeyInfo;
import org.bouncycastle.openssl.PEMKeyPair;
import org.bouncycastle.openssl.PEMParser;
import org.bouncycastle.openssl.jcajce.JcaPEMKeyConverter;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.TransactionDefinition;
import org.springframework.transaction.annotation.Propagation;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.transaction.support.TransactionTemplate;
import org.springframework.web.multipart.MultipartFile;

import javax.annotation.Resource;
import javax.persistence.EntityManager;
import javax.persistence.LockModeType;
import javax.persistence.PersistenceContext;
import java.io.*;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;
import java.nio.file.attribute.PosixFilePermissions;
import java.security.*;
import java.security.interfaces.RSAPrivateCrtKey;
import java.security.spec.RSAPublicKeySpec;
import java.time.LocalDateTime;
import java.util.*;
import java.util.stream.Collectors;

/**
 * 管理凭证只用于当前调用。云端配置成功后，仅保存专用用户私钥；
 * 同一 tenancy/用户名更新同一组区域记录，保留本地任务和实例的外键。
 */
@Service
@lombok.extern.slf4j.Slf4j
public class ManagedTenantImportService {
    @Resource private TenantRepository tenantRepository;
    @Resource private ManagedOciIdentityProvisioner provisioner;
    @Resource private PlatformTransactionManager transactionManager;
    @PersistenceContext private EntityManager entityManager;
    @Autowired(required = false) private OciAiClientManager aiClientManager;
    @Value("${baseFile.filePath}") private String baseFile;

    // 同一进程内串行处理，文件锁同时防止共享凭证目录的多进程覆盖。
    public synchronized Map<String, Object> save(String adminUserId, String tenancyId,
            String fingerprint, String region, String displayName, String managedUserName,
            String permissionsJson, String accountScopeJson, MultipartFile upload) throws Exception {
        adminUserId = required(adminUserId, "原 API 用户");
        tenancyId = required(tenancyId, "Tenancy OCID");
        displayName = required(displayName, "租户显示名称");
        managedUserName = validateManagedUserName(managedUserName);
        if (!adminUserId.startsWith("ocid1.user.") || !tenancyId.startsWith("ocid1.tenancy.")) {
            throw new IllegalArgumentException("请提供有效的 OCI 用户与租户 OCID");
        }
        if (upload == null || upload.isEmpty() || upload.getSize() > 65536) {
            throw new IllegalArgumentException("请选择有效的 RSA 私钥文件（最大 64 KB）");
        }
        Set<String> selected = selectedPermissions(permissionsJson);
        AccountPermissionScope scope = AccountPermissionScope.forSelection(accountScopeJson, selected);
        String regionId = RegionEnum.getRegionCode(required(region, "区域"));
        if (regionId == null || regionId.trim().isEmpty()) {
            throw new IllegalArgumentException("请选择有效的 OCI 区域");
        }
        byte[] adminKey = upload.getBytes();
        try {
            String actualFingerprint = fingerprint(adminKey);
            if (!actualFingerprint.equalsIgnoreCase(required(fingerprint, "指纹"))) {
                throw new IllegalArgumentException("原 API 私钥与指纹不匹配");
            }
            SimpleAuthenticationDetailsProvider adminProvider = SimpleAuthenticationDetailsProvider.builder()
                    .userId(adminUserId).tenantId(tenancyId).fingerprint(actualFingerprint)
                    .privateKeySupplier(() -> new ByteArrayInputStream(adminKey))
                    .region(Region.fromRegionId(regionId)).build();
            com.doubledimple.ociserver.config.TenantProxyBinder.applyForTenantId(null);
            Path directory = Paths.get(baseFile).toAbsolutePath().normalize().resolve("managed-oci");
            Files.createDirectories(directory);
            String identity = hex(MessageDigest.getInstance("SHA-256")
                    .digest((tenancyId + "\n" + managedUserName.toLowerCase(Locale.ROOT)).getBytes(StandardCharsets.UTF_8)), "");
            Path keyPath = directory.resolve(identity + ".pem");
            Path lockPath = directory.resolve(identity + ".lock");
            try (java.nio.channels.FileChannel lockFile = java.nio.channels.FileChannel.open(
                    lockPath, StandardOpenOption.CREATE, StandardOpenOption.WRITE);
                 java.nio.channels.FileLock lock = lockFile.tryLock()) {
                if (lock == null) throw new IllegalArgumentException("该专用用户正在更新，请稍后重试");
                return provisionAndSave(adminProvider, adminUserId, tenancyId, managedUserName,
                        displayName, selected, scope, keyPath);
            }
        } finally {
            Arrays.fill(adminKey, (byte) 0);
        }
    }

    /** Replace only the selected local account tree after the dedicated identity is ready. */
    public synchronized Map<String, Object> downgrade(Long tenantId, String managedUserName,
            String permissionsJson, String accountScopeJson, boolean backupConfirmed) throws Exception {
        TenantProxyBinder.clear();
        byte[] adminKey = null;
        try {
            if (!backupConfirmed) throw new IllegalArgumentException("请先导出并确认已备份原完整 API 凭证");
            managedUserName = validateManagedUserName(managedUserName);
            Set<String> selected = selectedPermissions(permissionsJson);
            AccountPermissionScope scope = AccountPermissionScope.forSelection(accountScopeJson, selected);
            MigrationSnapshot migration = new MigrationSnapshot(loadMigrationRows(tenantId, false));
            Tenant source = migration.parent;
            String adminUserId = required(source.getTenantId(), "原 API 用户");
            String tenancyId = required(source.getTenancy(), "Tenancy OCID");
            if (!adminUserId.startsWith("ocid1.user.") || !tenancyId.startsWith("ocid1.tenancy.")) {
                throw new IllegalArgumentException("原 API 的 OCI 用户或租户 OCID 无效");
            }
            assertNoManagedTarget(tenancyId, managedUserName);
            adminKey = readPrivateKey(source.getKeyFile());
            String actualFingerprint = fingerprint(adminKey);
            if (!actualFingerprint.equalsIgnoreCase(required(source.getFingerprint(), "指纹"))) {
                throw new IllegalArgumentException("原 API 私钥与指纹不匹配，未替换本地凭证");
            }
            final byte[] requestKey = adminKey;
            SimpleAuthenticationDetailsProvider provider = SimpleAuthenticationDetailsProvider.builder()
                    .userId(adminUserId).tenantId(tenancyId).fingerprint(actualFingerprint)
                    .privateKeySupplier(() -> new ByteArrayInputStream(requestKey))
                    .region(Region.fromRegionId(RegionEnum.getRegionCode(source.getRegion()))).build();
            TenantProxyBinder.applyForTenantId(source.getId());
            Path directory = Paths.get(baseFile).toAbsolutePath().normalize().resolve("managed-oci");
            Files.createDirectories(directory);
            String identity = hex(MessageDigest.getInstance("SHA-256")
                    .digest((tenancyId + "\n" + managedUserName.toLowerCase(Locale.ROOT)).getBytes(StandardCharsets.UTF_8)), "");
            Path keyPath = directory.resolve(identity + ".pem");
            // Separate source and target locks also serialize different target names for one local tree.
            try (java.nio.channels.FileChannel sourceLockFile = java.nio.channels.FileChannel.open(
                    directory.resolve("source-" + source.getId() + ".lock"), StandardOpenOption.CREATE, StandardOpenOption.WRITE);
                 java.nio.channels.FileLock sourceLock = sourceLockFile.tryLock();
                 java.nio.channels.FileChannel targetLockFile = java.nio.channels.FileChannel.open(
                    directory.resolve(identity + ".lock"), StandardOpenOption.CREATE, StandardOpenOption.WRITE);
                 java.nio.channels.FileLock targetLock = targetLockFile.tryLock()) {
                if (sourceLock == null || targetLock == null) {
                    throw new IllegalArgumentException("该 API 或专用用户正在更新，请稍后重试");
                }
                return provisionAndSave(provider, adminUserId, tenancyId, managedUserName,
                        required(source.getUserName(), "租户显示名称"), selected, scope, keyPath, migration);
            }
        } finally {
            if (adminKey != null) Arrays.fill(adminKey, (byte) 0);
            TenantProxyBinder.clear();
        }
    }

    private Map<String, Object> provisionAndSave(SimpleAuthenticationDetailsProvider provider,
            String adminUserId, String tenancyId, String managedUserName, String displayName,
            Set<String> selected, AccountPermissionScope scope, Path keyPath) throws Exception {
        return provisionAndSave(provider, adminUserId, tenancyId, managedUserName, displayName,
                selected, scope, keyPath, null);
    }

    private Map<String, Object> provisionAndSave(SimpleAuthenticationDetailsProvider provider,
            String adminUserId, String tenancyId, String managedUserName, String displayName,
            Set<String> selected, AccountPermissionScope scope, Path keyPath, MigrationSnapshot migration) throws Exception {
        // Ordinary source rows are never an ExistingIdentity or a fallback dedicated private key.
        if (migration != null) assertNoManagedTarget(tenancyId, managedUserName);
        List<Tenant> existingRows = migration != null ? Collections.emptyList() : tenantRepository.findByTenancy(tenancyId).stream()
                .filter(t -> OciPermissions.MODE.equals(t.getPermissionMode()))
                .filter(t -> managedUserName.equalsIgnoreCase(t.getManagedUserName()))
                .collect(Collectors.toList());
        Tenant existing = validateExistingRows(existingRows);
        ManagedOciIdentityProvisioner.ExistingIdentity previous = new ManagedOciIdentityProvisioner.ExistingIdentity();
        if (existing != null) {
            if (adminUserId.equals(existing.getTenantId())) {
                throw new IllegalArgumentException("专用用户不能是原 API 所属用户，请指定其他用户名");
            }
            previous.setUserId(existing.getTenantId());
            previous.setGroupId(existing.getManagedGroupId());
            previous.setPolicyId(existing.getManagedPolicyId());
            previous.setDomainId(existing.getManagedDomainId());
        }
        // 首次保存 DB 失败但私钥已写入时，重试仍可复用同一密钥。
        Path reusePath = Files.isRegularFile(keyPath) ? keyPath : existing != null
                && existing.getKeyFile() != null ? Paths.get(existing.getKeyFile()) : keyPath;
        if (migration != null) {
            for (Tenant source : migration.rows) {
                if (sameFile(reusePath, Paths.get(source.getKeyFile()))) {
                    throw new IllegalArgumentException("专用密钥路径与原 API 相同，请使用其他专用用户名");
                }
            }
        }
        if (Files.isRegularFile(reusePath)) {
            byte[] previousKey = Files.readAllBytes(reusePath);
            try {
                String keyFingerprint = fingerprint(previousKey);
                if (migration != null && keyFingerprint.equalsIgnoreCase(provider.getFingerprint())) {
                    throw new IllegalArgumentException("专用私钥不能复用原 API 私钥，请使用其他专用用户名");
                }
                if (reusePath.equals(keyPath) || existing == null || keyFingerprint.equalsIgnoreCase(existing.getFingerprint())) {
                    previous.setFingerprint(keyFingerprint);
                }
            } finally {
                Arrays.fill(previousKey, (byte) 0);
            }
        }
        ManagedOciIdentityProvisioner.Result result = provisioner.provision(provider, tenancyId,
                adminUserId, managedUserName, groupId -> OciPermissionCatalog.statements(groupId, selected, scope),
                previous, selected, scope);
        if (migration != null && (adminUserId.equals(result.getTargetUserId())
                || provider.getFingerprint().equalsIgnoreCase(result.getFingerprint()))) {
            if (result.getPrivateKeyPem() != null) Arrays.fill(result.getPrivateKeyPem(), (byte) 0);
            throw new IllegalArgumentException("专用用户及私钥必须与原 API 不同，未替换本地凭证");
        }
        byte[] newKey = result.getPrivateKeyPem();
        Path finalKeyPath = reusePath;
        if (newKey != null) {
            try {
                if (!fingerprint(newKey).equalsIgnoreCase(result.getFingerprint())) {
                    throw new IllegalStateException("生成的专用密钥与云端指纹不匹配");
                }
                writePrivateKey(keyPath, newKey);
                finalKeyPath = keyPath;
            } finally {
                Arrays.fill(newKey, (byte) 0);
            }
        }
        if (!Files.isRegularFile(finalKeyPath)) {
            throw new IllegalArgumentException("本地专用私钥不存在，请重新配置专用用户");
        }
        final String savedKey = finalKeyPath.toString();
        TransactionTemplate transaction = new TransactionTemplate(transactionManager);
        // Cleanup must follow a real commit, even when another caller has an ambient transaction.
        if (migration != null) transaction.setPropagationBehavior(TransactionDefinition.PROPAGATION_REQUIRES_NEW);
        List<Tenant> saved = transaction.execute(status -> {
            List<Tenant> rows = existingRows;
            if (migration != null) {
                rows = loadMigrationRows(migration.parent.getId(), true);
                migration.requireUnchanged(rows);
                assertNoManagedTarget(tenancyId, managedUserName);
            }
            return saveRows(rows, result, tenancyId, managedUserName, displayName, selected, scope, savedKey,
                    migration != null);
        });
        List<String> cleanupWarnings = migration == null ? Collections.emptyList() : afterMigrationCommitted(migration);
        Map<String, Object> response = new LinkedHashMap<>();
        Tenant parent = saved.stream().filter(t -> t.getParenId() == null || t.getParenId() == 0L)
                .findFirst().orElseThrow(() -> new IllegalStateException("主区域保存失败"));
        response.put("id", parent.getId().toString());
        response.put("managedUserName", managedUserName);
        response.put("permissions", selected);
        response.put("accountScope", JSON.parseObject(scope.toJson()));
        if (!cleanupWarnings.isEmpty()) response.put("cleanupWarnings", cleanupWarnings);
        response.put("message", migration == null ? "专用用户权限已更新。OCI 跨区域权限同步可能需要数分钟。"
                : "已替换为专用受限 API，原区域、实例和任务记录已保留；OCI 原用户和 API 密钥未删除。权限同步可能需要数分钟。");
        return response;
    }

    private List<Tenant> saveRows(List<Tenant> existingRows, ManagedOciIdentityProvisioner.Result result,
            String tenancyId, String managedUserName, String displayName, Set<String> selected,
            AccountPermissionScope scope, String keyPath, boolean preserveNames) {
        Map<String, Tenant> byRegion = existingRows.stream()
                .collect(Collectors.toMap(t -> RegionEnum.getRegionCode(t.getRegion()), t -> t, (a, b) -> a));
        Tenant parent = existingRows.stream().filter(t -> t.getParenId() == null || t.getParenId() == 0L)
                .findFirst().orElse(null);
        if (parent != null && !Objects.equals(RegionEnum.getRegionCode(parent.getRegion()), result.getHomeRegion())) {
            throw new IllegalArgumentException("本地主区域与 OCI 主区域不同，请先恢复正确的区域记录");
        }
        long parentId = parent == null ? IdUtil.getSnowflakeNextId() : parent.getId();
        List<Tenant> rows = new ArrayList<>(existingRows);
        for (RegionSubscription subscription : result.getRegions()) {
            String region = subscription.getRegionName();
            Tenant row = byRegion.get(region);
            if (row == null) {
                row = new Tenant();
                row.setId(Boolean.TRUE.equals(subscription.getIsHomeRegion()) ? parentId : IdUtil.getSnowflakeNextId());
                row.setCreatedAt(LocalDateTime.now());
                row.setRegion(region);
                row.setAccountType("UN_KNOW_ACCOUNT");
                rows.add(row);
            }
            row.setIsHomeRegion(Boolean.TRUE.equals(subscription.getIsHomeRegion()));
            row.setParenId(Boolean.TRUE.equals(subscription.getIsHomeRegion()) ? 0L : parentId);
        }
        if (rows.isEmpty() || rows.stream().noneMatch(t -> t.getParenId() != null && t.getParenId() == 0L)) {
            throw new IllegalArgumentException("未获取到 OCI 主区域，未保存租户");
        }
        for (Tenant row : rows) {
            row.setCloudType(1);
            row.setTenantId(result.getTargetUserId());
            row.setTenancy(tenancyId);
            if (!preserveNames || row.getUserName() == null) row.setUserName(displayName);
            row.setTenancyName(result.getTenancyName());
            row.setTenancyDes(result.getTenancyDescription());
            row.setFingerprint(result.getFingerprint());
            row.setIdStr(row.getId().toString());
            row.setKeyFile(keyPath);
            row.setPermissionMode(OciPermissions.MODE);
            row.setPermissionsJson(OciPermissionCatalog.serialize(selected));
            row.setManagedUserName(managedUserName);
            row.setManagedGroupId(result.getGroupId());
            row.setManagedPolicyId(result.getPolicyId());
            row.setAccountScopeJson(scope.toJson());
            row.setManagedDomainId(result.getDomainId());
            row.setManagedDomainUrl(result.getDomainUrl());
            row.setManagedDomainGrantsJson(result.getDomainGrantsJson());
            row.setActive(true);
        }
        return tenantRepository.saveAll(rows);
    }

    private List<Tenant> loadMigrationRows(Long tenantId, boolean forUpdate) {
        if (tenantId == null || tenantId <= 0) throw new IllegalArgumentException("租户 ID 无效，请重新选择租户");
        Tenant parent = tenantRepository.findById(tenantId)
                .orElseThrow(() -> new IllegalArgumentException("租户记录已删除，请刷新后重试"));
        // An OpenEntityManagerInView context may still hold the entity from before provisioning.
        // Refresh under a write lock instead of trusting a repeated repository lookup's cached instance.
        if (forUpdate) entityManager.refresh(parent, LockModeType.PESSIMISTIC_WRITE);
        // Old root rows can lack isHomeRegion. The OCI result validates their actual region in saveRows.
        if (parent.getParenId() != null && parent.getParenId() != 0L) {
            throw new IllegalArgumentException("请从普通 OCI API 的主区域记录执行降权");
        }
        if (parent.getTransferStatus() != 0) throw new IllegalArgumentException("已转移的租户不能执行 API 降权");
        List<Tenant> rows = new ArrayList<>();
        rows.add(parent);
        List<Tenant> children = tenantRepository.findByParenId(parent.getId());
        for (Tenant child : children) {
            if (forUpdate) entityManager.refresh(child, LockModeType.PESSIMISTIC_WRITE);
            rows.add(child);
        }
        Set<String> regions = new HashSet<>();
        Set<Long> ids = new HashSet<>();
        for (Tenant row : rows) {
            if (row.getCloudType() != 1 || OciPermissions.isManaged(row)) {
                throw new IllegalArgumentException("仅普通 OCI API 可以降权，受限 API 请使用授权更新");
            }
            String region = RegionEnum.getRegionCode(required(row.getRegion(), "区域"));
            if (region == null || region.trim().isEmpty() || !regions.add(region) || !ids.add(row.getId())
                    || !Objects.equals(parent.getTenantId(), row.getTenantId())
                    || !Objects.equals(parent.getTenancy(), row.getTenancy())
                    || !required(parent.getFingerprint(), "指纹").equalsIgnoreCase(required(row.getFingerprint(), "指纹"))
                    || (!Objects.equals(parent.getId(), row.getId())
                    && (!Objects.equals(parent.getId(), row.getParenId()) || row.getIsHomeRegion()))) {
                throw new IllegalArgumentException("原 API 的区域或凭证记录不一致，请先恢复租户记录");
            }
            required(row.getKeyFile(), "原 API 私钥路径");
        }
        return rows;
    }

    private void assertNoManagedTarget(String tenancyId, String managedUserName) {
        boolean exists = tenantRepository.findByTenancy(tenancyId).stream()
                .anyMatch(t -> t.getCloudType() == 1 && OciPermissions.isManaged(t)
                        && managedUserName.equalsIgnoreCase(t.getManagedUserName()));
        if (exists) throw new IllegalArgumentException("该专用用户名已有受限 API 记录，请使用其他专用用户名");
    }

    private List<String> afterMigrationCommitted(MigrationSnapshot migration) {
        Set<String> warnings = new LinkedHashSet<>();
        if (aiClientManager != null) {
            for (Tenant old : migration.rows) {
                try {
                    aiClientManager.removeClient(old);
                } catch (RuntimeException e) {
                    warnings.add("API 已完成降权，部分旧 AI 连接未及时释放，请稍后重试相关功能。");
                    log.warn("降权后释放旧 AI 连接失败，异常类型:{}", e.getClass().getSimpleName());
                }
            }
        }
        try {
            Path base = Paths.get(baseFile).toAbsolutePath().normalize();
            Path realBase = base.toRealPath();
            List<Tenant> remaining = tenantRepository.findAll();
            Set<Path> inspected = new HashSet<>();
            for (Tenant old : migration.rows) {
                Path candidate = Paths.get(old.getKeyFile()).toAbsolutePath().normalize();
                if (!inspected.add(candidate) || !Files.exists(candidate, LinkOption.NOFOLLOW_LINKS)) continue;
                if (!candidate.startsWith(base) || Files.isSymbolicLink(candidate)
                        || !Files.isRegularFile(candidate, LinkOption.NOFOLLOW_LINKS)
                        || !candidate.toRealPath().startsWith(realBase)) {
                    warnings.add("原私钥文件位于托管目录之外或使用符号链接，已保留；请确认备份后自行清理。");
                    continue;
                }
                boolean referenced = false;
                for (Tenant other : remaining) {
                    if (other.getKeyFile() != null && !other.getKeyFile().trim().isEmpty()
                            && sameFile(candidate, Paths.get(other.getKeyFile()))) {
                        referenced = true;
                        break;
                    }
                }
                if (referenced) {
                    warnings.add("原私钥文件仍被其他本地 API 引用，已保留以免影响这些 API。");
                    continue;
                }
                // Never delete an unrelated upload if a stored path's contents changed during provisioning.
                byte[] oldKey = readPrivateKey(candidate.toString());
                try {
                    if (!fingerprint(oldKey).equalsIgnoreCase(old.getFingerprint())) {
                        warnings.add("原私钥文件内容已变化，已保留；请确认备份后自行清理。");
                        continue;
                    }
                } finally {
                    Arrays.fill(oldKey, (byte) 0);
                }
                Files.deleteIfExists(candidate);
            }
        } catch (Exception e) {
            // The database transaction has committed; report incomplete cleanup without claiming rollback.
            warnings.add("API 已完成降权，但部分旧私钥文件未能清理，请确认备份后手动清理。");
            log.warn("降权后清理本地旧私钥失败，异常类型:{}", e.getClass().getSimpleName());
        }
        return new ArrayList<>(warnings);
    }

    private static boolean sameFile(Path first, Path second) throws IOException {
        if (first.toAbsolutePath().normalize().equals(second.toAbsolutePath().normalize())) return true;
        return Files.exists(first) && Files.exists(second) && Files.isSameFile(first, second);
    }

    private static byte[] readPrivateKey(String filename) {
        try (InputStream input = Files.newInputStream(Paths.get(filename));
             ByteArrayOutputStream output = new ByteArrayOutputStream()) {
            byte[] buffer = new byte[4096];
            try {
                int length;
                while ((length = input.read(buffer)) != -1) {
                    if (output.size() + length > 65536) throw new IOException("Oversized key");
                    output.write(buffer, 0, length);
                }
                if (output.size() == 0) throw new IOException("Empty key");
                return output.toByteArray();
            } finally {
                Arrays.fill(buffer, (byte) 0);
            }
        } catch (Exception e) {
            throw new IllegalArgumentException("无法读取原 API 私钥，请恢复有效私钥后重试");
        }
    }

    private static String validateManagedUserName(String value) {
        String name = required(value, "专用用户名");
        if (!name.matches("[A-Za-z0-9][A-Za-z0-9_.+@-]{0,99}")) {
            throw new IllegalArgumentException("专用用户名限 1–100 个英文字母、数字及 _.+@-");
        }
        return name;
    }

    private static Set<String> selectedPermissions(String json) {
        try {
            List<String> requested = JSON.parseArray(json, String.class);
            if (requested == null) throw new IllegalArgumentException();
            return OciPermissionCatalog.normalize(requested);
        } catch (RuntimeException e) {
            throw new IllegalArgumentException("权限选择无效，或包含暂不支持独立授权的操作");
        }
    }

    private static final class MigrationSnapshot {
        private final List<Tenant> rows = new ArrayList<>();
        private final Map<Long, List<Object>> identities;
        private final Tenant parent;

        private MigrationSnapshot(List<Tenant> source) {
            for (Tenant row : source) {
                Tenant copy = new Tenant();
                org.springframework.beans.BeanUtils.copyProperties(row, copy, "children", "registerDetail");
                rows.add(copy);
            }
            parent = rows.get(0);
            identities = identities(rows);
        }

        private void requireUnchanged(List<Tenant> current) {
            if (!identities.equals(identities(current))) {
                throw new IllegalArgumentException("原 API 或区域记录在降权期间已变更，未替换本地凭证，请刷新后重试");
            }
        }

        private static Map<Long, List<Object>> identities(List<Tenant> rows) {
            Map<Long, List<Object>> result = new HashMap<>();
            for (Tenant row : rows) {
                result.put(row.getId(), Arrays.asList(row.getParenId(), RegionEnum.getRegionCode(row.getRegion()),
                        row.getTenantId(), row.getTenancy(), row.getFingerprint(), row.getKeyFile(), row.getCloudType(),
                        row.getPermissionMode(), row.getManagedUserName(), row.getManagedGroupId(), row.getManagedPolicyId(),
                        row.getManagedDomainId(), row.getManagedDomainUrl(), row.getManagedDomainGrantsJson(),
                        row.getPermissionsJson(), row.getAccountScopeJson(), row.getUserName(), row.getIsHomeRegion(),
                        row.getActive(), row.getTransferStatus()));
            }
            return result;
        }
    }

    /** 普通同步只用专用凭证读取区域，保留用户、权限和本地资源主键。 */
    @Transactional(propagation = Propagation.REQUIRES_NEW)
    public synchronized List<Tenant> refreshRegions(Tenant tenant) {
        // A caller may still hold an entity loaded before a permissions update.
        Tenant current = tenantRepository.findById(tenant.getId())
                .orElseThrow(() -> new IllegalArgumentException("租户记录已删除"));
        if (!OciPermissions.MODE.equals(current.getPermissionMode())) {
            throw new IllegalArgumentException("租户授权模式已变化，请刷新后重试");
        }
        List<Tenant> rows = tenantRepository.findByTenantId(current.getTenantId()).stream()
                .filter(t -> current.getTenancy().equals(t.getTenancy()))
                .filter(t -> OciPermissions.MODE.equals(t.getPermissionMode()))
                .filter(t -> Objects.equals(current.getManagedGroupId(), t.getManagedGroupId()))
                .collect(Collectors.toList());
        Tenant parent = validateExistingRows(rows);
        if (parent == null) throw new IllegalArgumentException("未找到主区域记录");
        Set<String> existing = rows.stream().map(t -> RegionEnum.getRegionCode(t.getRegion())).collect(Collectors.toSet());
        List<RegionSubscription> subscriptions = OciUtils.queryRegions(OciUtils.getProvider(parent));
        if (subscriptions == null || subscriptions.isEmpty()) {
            throw new IllegalArgumentException("无法读取已订阅区域，请检查专用 API 的权限及 OCI 同步状态");
        }
        for (RegionSubscription sub : subscriptions) {
            if (!existing.add(sub.getRegionName())) continue;
            Tenant child = new Tenant();
            org.springframework.beans.BeanUtils.copyProperties(parent, child);
            child.setId(IdUtil.getSnowflakeNextId());
            child.setIdStr(child.getId().toString());
            child.setParenId(parent.getId());
            child.setRegion(sub.getRegionName());
            child.setIsHomeRegion(false);
            child.setChildren(null);
            child.setCreatedAt(LocalDateTime.now());
            rows.add(child);
        }
        return tenantRepository.saveAll(rows);
    }

    private Tenant validateExistingRows(List<Tenant> rows) {
        if (rows.isEmpty()) return null;
        List<Tenant> parents = rows.stream()
                .filter(t -> t.getParenId() == null || t.getParenId() == 0L)
                .collect(Collectors.toList());
        if (parents.size() != 1) {
            throw new IllegalArgumentException("专用用户的本地区域记录缺少唯一父记录，请先恢复租户记录");
        }
        Tenant parent = parents.get(0);
        Set<String> regions = new HashSet<>();
        for (Tenant row : rows) {
            String region = RegionEnum.getRegionCode(row.getRegion());
            if (region == null || !regions.add(region)
                    || !Objects.equals(parent.getTenantId(), row.getTenantId())
                    || !Objects.equals(parent.getManagedGroupId(), row.getManagedGroupId())
                    || !Objects.equals(parent.getManagedPolicyId(), row.getManagedPolicyId())
                    || !Objects.equals(parent.getManagedDomainId(), row.getManagedDomainId())
                    || !Objects.equals(parent.getAccountScopeJson(), row.getAccountScopeJson())
                    || (!Objects.equals(parent.getId(), row.getId())
                    && !Objects.equals(parent.getId(), row.getParenId()))) {
                throw new IllegalArgumentException("专用用户的区域或授权记录不一致，请先恢复租户记录");
            }
        }
        return parent;
    }

    private static void writePrivateKey(Path destination, byte[] key) throws IOException {
        Path temporary = null;
        try {
            try {
                temporary = Files.createTempFile(destination.getParent(), ".key-", ".tmp",
                        PosixFilePermissions.asFileAttribute(PosixFilePermissions.fromString("rw-------")));
            } catch (UnsupportedOperationException e) {
                temporary = Files.createTempFile(destination.getParent(), ".key-", ".tmp");
                File file = temporary.toFile();
                if (!file.setReadable(false, false) || !file.setWritable(false, false)
                        || !file.setReadable(true, true) || !file.setWritable(true, true)) {
                    throw new IOException("无法限制私钥文件权限");
                }
            }
            Files.write(temporary, key, StandardOpenOption.TRUNCATE_EXISTING);
            try {
                Files.move(temporary, destination, StandardCopyOption.ATOMIC_MOVE, StandardCopyOption.REPLACE_EXISTING);
            } catch (AtomicMoveNotSupportedException e) {
                Files.move(temporary, destination, StandardCopyOption.REPLACE_EXISTING);
            }
        } finally {
            if (temporary != null) Files.deleteIfExists(temporary);
        }
    }

    private static String required(String value, String field) {
        if (value == null || value.trim().isEmpty()) throw new IllegalArgumentException(field + "不能为空");
        return value.trim();
    }

    private static String fingerprint(byte[] pem) {
        try (PEMParser parser = new PEMParser(new InputStreamReader(new ByteArrayInputStream(pem), StandardCharsets.UTF_8))) {
            Object parsed = parser.readObject();
            JcaPEMKeyConverter converter = new JcaPEMKeyConverter();
            PrivateKey key = parsed instanceof PEMKeyPair ? converter.getKeyPair((PEMKeyPair) parsed).getPrivate()
                    : parsed instanceof PrivateKeyInfo ? converter.getPrivateKey((PrivateKeyInfo) parsed) : null;
            if (!(key instanceof RSAPrivateCrtKey)) throw new IllegalArgumentException();
            RSAPrivateCrtKey rsa = (RSAPrivateCrtKey) key;
            if (rsa.getModulus().bitLength() < 2048) throw new IllegalArgumentException();
            byte[] publicKey = KeyFactory.getInstance("RSA").generatePublic(
                    new RSAPublicKeySpec(rsa.getModulus(), rsa.getPublicExponent())).getEncoded();
            return hex(MessageDigest.getInstance("MD5").digest(publicKey), ":");
        } catch (Exception e) {
            throw new IllegalArgumentException("请选择至少 2048 位、未加密的 OCI RSA 私钥");
        }
    }

    private static String hex(byte[] value, String separator) {
        StringJoiner result = new StringJoiner(separator);
        for (byte b : value) result.add(String.format(Locale.ROOT, "%02x", b & 0xff));
        return result.toString();
    }
}
