package com.doubledimple.ociserver.service.permissions;

import cn.hutool.core.util.IdUtil;
import com.alibaba.fastjson2.JSON;
import com.doubledimple.dao.entity.Tenant;
import com.doubledimple.dao.repository.TenantRepository;
import com.doubledimple.ocicommon.enums.RegionEnum;
import com.doubledimple.ociserver.utils.oracle.OciUtils;
import com.oracle.bmc.Region;
import com.oracle.bmc.auth.SimpleAuthenticationDetailsProvider;
import com.oracle.bmc.identity.model.RegionSubscription;
import org.bouncycastle.asn1.pkcs.PrivateKeyInfo;
import org.bouncycastle.openssl.PEMKeyPair;
import org.bouncycastle.openssl.PEMParser;
import org.bouncycastle.openssl.jcajce.JcaPEMKeyConverter;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.annotation.Propagation;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.transaction.support.TransactionTemplate;
import org.springframework.web.multipart.MultipartFile;

import javax.annotation.Resource;
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
public class ManagedTenantImportService {
    @Resource private TenantRepository tenantRepository;
    @Resource private ManagedOciIdentityProvisioner provisioner;
    @Resource private PlatformTransactionManager transactionManager;
    @Value("${baseFile.filePath}") private String baseFile;

    // 同一进程内串行处理，文件锁同时防止共享凭证目录的多进程覆盖。
    public synchronized Map<String, Object> save(String adminUserId, String tenancyId,
            String fingerprint, String region, String displayName, String managedUserName,
            String permissionsJson, String accountScopeJson, MultipartFile upload) throws Exception {
        adminUserId = required(adminUserId, "原 API 用户");
        tenancyId = required(tenancyId, "Tenancy OCID");
        displayName = required(displayName, "租户显示名称");
        managedUserName = required(managedUserName, "专用用户名");
        if (!managedUserName.matches("[A-Za-z0-9][A-Za-z0-9_.+@-]{0,99}")) {
            throw new IllegalArgumentException("专用用户名限 1–100 个英文字母、数字及 _.+@-");
        }
        if (!adminUserId.startsWith("ocid1.user.") || !tenancyId.startsWith("ocid1.tenancy.")) {
            throw new IllegalArgumentException("请提供有效的 OCI 用户与租户 OCID");
        }
        if (upload == null || upload.isEmpty() || upload.getSize() > 65536) {
            throw new IllegalArgumentException("请选择有效的 RSA 私钥文件（最大 64 KB）");
        }
        Set<String> selected;
        try {
            List<String> requested = JSON.parseArray(permissionsJson, String.class);
            if (requested == null) throw new IllegalArgumentException();
            selected = OciPermissionCatalog.normalize(requested);
        } catch (RuntimeException e) {
            throw new IllegalArgumentException("权限选择无效，或包含暂不支持独立授权的操作");
        }
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

    private Map<String, Object> provisionAndSave(SimpleAuthenticationDetailsProvider provider,
            String adminUserId, String tenancyId, String managedUserName, String displayName,
            Set<String> selected, AccountPermissionScope scope, Path keyPath) throws Exception {
        List<Tenant> existingRows = tenantRepository.findByTenancy(tenancyId).stream()
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
        if (Files.isRegularFile(reusePath)) {
            byte[] previousKey = Files.readAllBytes(reusePath);
            try {
                String keyFingerprint = fingerprint(previousKey);
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
        List<Tenant> saved = new TransactionTemplate(transactionManager).execute(status -> saveRows(
                existingRows, result, tenancyId, managedUserName, displayName, selected, scope, savedKey));
        Map<String, Object> response = new LinkedHashMap<>();
        Tenant parent = saved.stream().filter(t -> t.getParenId() == null || t.getParenId() == 0L)
                .findFirst().orElseThrow(() -> new IllegalStateException("主区域保存失败"));
        response.put("id", parent.getId().toString());
        response.put("managedUserName", managedUserName);
        response.put("permissions", selected);
        response.put("accountScope", JSON.parseObject(scope.toJson()));
        response.put("message", "专用用户权限已更新。OCI 跨区域权限同步可能需要数分钟。");
        return response;
    }

    private List<Tenant> saveRows(List<Tenant> existingRows, ManagedOciIdentityProvisioner.Result result,
            String tenancyId, String managedUserName, String displayName, Set<String> selected,
            AccountPermissionScope scope, String keyPath) {
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
            row.setUserName(displayName);
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
