package com.doubledimple.dao.repository;

import com.doubledimple.dao.entity.DnsRecord;
import com.doubledimple.ocicommon.enums.ProviderType;
import com.doubledimple.ocicommon.enums.RecordStatus;
import com.doubledimple.ocicommon.enums.RecordType;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.JpaSpecificationExecutor;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import org.springframework.stereotype.Repository;

import java.time.LocalDateTime;
import java.util.List;
import java.util.Optional;

@Repository
public interface DnsRecordRepository extends JpaRepository<DnsRecord, Long>, JpaSpecificationExecutor<DnsRecord> {

    /**
     * 根据更新时间倒序查找第一条记录
     */
    Optional<DnsRecord> findFirstByOrderByUpdateTimeDesc();

    List<DnsRecord> findByZoneIdAndProviderTypeAndRecordType(String zoneId, ProviderType providerType, RecordType recordType);


    /**
     * 根据ID升序查找第一条记录
     */
    Optional<DnsRecord> findFirstByOrderByIdAsc();

    /**
     * 根据服务商类型查找DNS记录
     */
    List<DnsRecord> findByProviderType(ProviderType providerType);

    List<DnsRecord> findByZoneIdAndProviderType(String zoneId, ProviderType providerType);

    /**
     * 根据域名查找DNS记录
     */
    List<DnsRecord> findByDomainName(String domainName);

    /**
     * 根据服务商类型和域名查找DNS记录
     */
    List<DnsRecord> findByProviderTypeAndDomainName(ProviderType providerType, String domainName);

    /**
     * 根据服务商记录ID查找DNS记录
     */
    Optional<DnsRecord> findByProviderRecordId(String providerRecordId);

    /**
     * 根据Zone ID查找DNS记录（Cloudflare专用）
     */
    List<DnsRecord> findByZoneId(String zoneId);

    /**
     * 根据记录类型查找DNS记录
     */
    List<DnsRecord> findByRecordType(RecordType recordType);

    /**
     * 根据状态查找DNS记录
     */
    List<DnsRecord> findByStatus(RecordStatus status);

    /**
     * 根据域名和记录名称查找DNS记录
     */
    List<DnsRecord> findByDomainNameAndRecordName(String domainName, String recordName);

    /**
     * 根据域名、记录名称和记录类型查找DNS记录（用于检查重复）
     */
    Optional<DnsRecord> findByDomainNameAndRecordNameAndRecordType(
            String domainName, String recordName, RecordType recordType);

    /**
     * 根据服务商类型和状态查找DNS记录
     */
    List<DnsRecord> findByProviderTypeAndStatus(ProviderType providerType, RecordStatus status);

    /**
     * 查找需要同步的记录（最后同步时间早于指定时间或为空）
     */
    @Query("SELECT d FROM DnsRecord d WHERE d.lastSyncTime IS NULL OR d.lastSyncTime < :syncTime")
    List<DnsRecord> findRecordsNeedSync(@Param("syncTime") LocalDateTime syncTime);

    /**
     * 根据服务商类型查找需要同步的记录
     */
    @Query("SELECT d FROM DnsRecord d WHERE d.providerType = :providerType AND (d.lastSyncTime IS NULL OR d.lastSyncTime < :syncTime)")
    List<DnsRecord> findRecordsNeedSyncByProvider(@Param("providerType") ProviderType providerType,
                                                  @Param("syncTime") LocalDateTime syncTime);

    /**
     * 统计指定服务商的记录数量
     */
    long countByProviderType(ProviderType providerType);

    /**
     * 统计指定域名的记录数量
     */
    long countByDomainName(String domainName);

    /**
     * 统计指定状态的记录数量
     */
    long countByStatus(RecordStatus status);

    /**
     * 查找指定域名的所有记录类型
     */
    @Query("SELECT DISTINCT d.recordType FROM DnsRecord d WHERE d.domainName = :domainName")
    List<RecordType> findDistinctRecordTypesByDomain(@Param("domainName") String domainName);

    /**
     * 查找所有不同的域名
     */
    @Query("SELECT DISTINCT d.domainName FROM DnsRecord d ORDER BY d.domainName")
    List<String> findAllDistinctDomains();

    /**
     * 根据服务商查找所有不同的域名
     */
    @Query("SELECT DISTINCT d.domainName FROM DnsRecord d WHERE d.providerType = :providerType ORDER BY d.domainName")
    List<String> findDistinctDomainsByProvider(@Param("providerType") ProviderType providerType);

    /**
     * 查找启用代理的Cloudflare记录
     */
    @Query("SELECT d FROM DnsRecord d WHERE d.providerType = 'CLOUDFLARE' AND d.proxied = true")
    List<DnsRecord> findCloudflareProxiedRecords();

    /**
     * 根据记录值模糊查找
     */
    List<DnsRecord> findByRecordValueContaining(String recordValue);

    /**
     * 根据IP地址、记录类型和服务商查找
     */
    List<DnsRecord> findByRecordValueAndRecordTypeAndProviderType(String recordValue, RecordType recordType, ProviderType providerType);

    /**
     * 查找指定服务商中指定IP的所有A记录
     */
    @Query("SELECT d FROM DnsRecord d WHERE d.providerType = :providerType AND d.recordValue = :ipAddress AND d.recordType = com.doubledimple.ocicommon.enums.RecordType.A")
    List<DnsRecord> findARecordsByIpAndProvider(@Param("ipAddress") String ipAddress,
                                                @Param("providerType") ProviderType providerType);

    /**
     * 查找指定服务商中指定IP的所有AAAA记录
     */
    @Query("SELECT d FROM DnsRecord d WHERE d.providerType = :providerType AND d.recordValue = :ipAddress AND d.recordType = com.doubledimple.ocicommon.enums.RecordType.AAAA")
    List<DnsRecord> findAAAARecordsByIpAndProvider(@Param("ipAddress") String ipAddress,
                                                   @Param("providerType") ProviderType providerType);


    /**
     * 查找指定服务商中使用多个IP地址的记录
     */
    @Query("SELECT d FROM DnsRecord d WHERE d.providerType = :providerType AND d.recordValue IN :ipAddresses")
    List<DnsRecord> findByRecordValueInAndProvider(@Param("ipAddresses") List<String> ipAddresses, @Param("providerType") ProviderType providerType);

    /**
     * 根据IP段和服务商查找记录（模糊匹配，如：47.79.95.%）
     */
    @Query("SELECT d FROM DnsRecord d WHERE d.providerType = :providerType AND d.recordValue LIKE :ipPattern")
    List<DnsRecord> findByIpPatternAndProvider(@Param("ipPattern") String ipPattern, @Param("providerType") ProviderType providerType);

    /**
     * 查找Cloudflare中使用指定IP且已代理的记录
     */
    @Query("SELECT d FROM DnsRecord d WHERE d.providerType = :providerType AND d.recordValue = :ipAddress AND d.proxied = true")
    List<DnsRecord> findCloudflareProxiedRecordsByIp(@Param("ipAddress") String ipAddress, @Param("providerType") ProviderType providerType);

    /**
     * 使用指定IP且仅DNS的记录
     */
    @Query("SELECT d FROM DnsRecord d WHERE d.providerType = :providerType AND d.recordValue = :ipAddress AND (d.proxied = false OR d.proxied IS NULL)")
    List<DnsRecord> findCloudflareNonProxiedRecordsByIp(@Param("ipAddress") String ipAddress, @Param("providerType") ProviderType providerType);

    /**
     * 查找指定服务商中指定域名使用指定IP的记录
     */
    @Query("SELECT d FROM DnsRecord d WHERE d.providerType = :providerType AND d.domainName = :domainName AND d.recordValue = :ipAddress")
    List<DnsRecord> findByIpAndDomainAndProvider(@Param("ipAddress") String ipAddress, @Param("domainName") String domainName, @Param("providerType") ProviderType providerType);

    /**
     * 查找指定服务商中不同域名但使用相同IP的记录
     */
    @Query("SELECT d FROM DnsRecord d WHERE d.providerType = :providerType AND d.recordValue = :ipAddress GROUP BY d.domainName")
    List<DnsRecord> findDistinctDomainsByIpAndProvider(@Param("ipAddress") String ipAddress, @Param("providerType") ProviderType providerType);

    /**
     * 获取指定服务商中所有不同的IP地址
     */
    @Query("SELECT DISTINCT d.recordValue FROM DnsRecord d WHERE d.providerType = :providerType ORDER BY d.recordValue")
    List<String> findAllDistinctIpsByProvider(@Param("providerType") ProviderType providerType);

    /**
     * 根据IP地址精确查找DNS记录
     */
    List<DnsRecord> findByRecordValue(String recordValue);

    /**
     * 根据IP地址查找A记录
     */
    List<DnsRecord> findByRecordValueAndRecordType(String recordValue, RecordType recordType);

    /**
     * 查找指定IP的所有A记录
     */
    @Query("SELECT d FROM DnsRecord d WHERE d.recordValue = :ipAddress AND d.recordType = 'A'")
    List<DnsRecord> findARecordsByIp(@Param("ipAddress") String ipAddress);

    /**
     * 查找指定IP的所有AAAA记录
     */
    @Query("SELECT d FROM DnsRecord d WHERE d.recordValue = :ipAddress AND d.recordType = 'AAAA'")
    List<DnsRecord> findAAAARecordsByIp(@Param("ipAddress") String ipAddress);

    /**
     * 根据IP地址和服务商查找记录
     */
    List<DnsRecord> findByRecordValueAndProviderType(String recordValue, ProviderType providerType);

    /**
     * 查找使用相同IP的所有记录（不同域名）
     */
    @Query("SELECT d FROM DnsRecord d WHERE d.recordValue = :ipAddress ORDER BY d.domainName, d.recordName")
    List<DnsRecord> findAllRecordsByIp(@Param("ipAddress") String ipAddress);

    /**
     * 统计使用指定IP的记录数量
     */
    @Query("SELECT COUNT(d) FROM DnsRecord d WHERE d.recordValue = :ipAddress")
    long countRecordsByIp(@Param("ipAddress") String ipAddress);

    /**
     * 查找使用多个IP地址的记录
     */
    @Query("SELECT d FROM DnsRecord d WHERE d.recordValue IN :ipAddresses")
    List<DnsRecord> findByRecordValueIn(@Param("ipAddresses") List<String> ipAddresses);

    /**
     * 根据IP段查找记录（模糊匹配）
     */
    @Query("SELECT d FROM DnsRecord d WHERE d.recordValue LIKE :ipPattern")
    List<DnsRecord> findByIpPattern(@Param("ipPattern") String ipPattern);

    /**
     * 查找指定时间段内创建的记录
     */
    List<DnsRecord> findByCreateTimeBetween(LocalDateTime startTime, LocalDateTime endTime);

    /**
     * 查找指定时间段内更新的记录
     */
    List<DnsRecord> findByUpdateTimeBetween(LocalDateTime startTime, LocalDateTime endTime);

    /**
     * 删除指定服务商的所有记录
     */
    void deleteByProviderType(ProviderType providerType);

    /**
     * 删除指定域名的所有记录
     */
    void deleteByDomainName(String domainName);

    /**
     * 根据服务商记录ID删除
     */
    void deleteByProviderRecordId(String providerRecordId);

    /**
     * 检查记录是否存在（根据服务商记录ID）
     */
    boolean existsByProviderRecordId(String providerRecordId);

    /**
     * 检查域名记录是否存在
     */
    boolean existsByDomainNameAndRecordNameAndRecordType(
            String domainName, String recordName, RecordType recordType);
}
