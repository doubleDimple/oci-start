package com.doubledimple.dao.repository;

import com.doubledimple.dao.entity.BootInstance;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.JpaSpecificationExecutor;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import org.springframework.stereotype.Repository;
import org.springframework.transaction.annotation.Transactional;

import java.sql.Timestamp;
import java.util.List;

@Repository
public interface BootInstanceRepository extends JpaRepository<BootInstance, Long>, JpaSpecificationExecutor<BootInstance> {
    // Additional query methods can be added here if needed

    List<BootInstance> queryBootInstanceByTenantId(long tenantId);

    /**
     * 根据状态查询实例
     * @param status
     * @return
     */
    List<BootInstance> queryBootInstancesByStatus(int status);

    Long queryAddCountByBootId(Long bootId);


    /*@Modifying
    @Query("UPDATE BootInstance u SET u.status = :status WHERE u.id = :id")
    int updateBootInstanceStatusById(@Param("id") Long id, @Param("status") Integer status);*/

    @Modifying
    @Query("UPDATE BootInstance u SET u.status = :status, u.lastResetDate = CURRENT_DATE WHERE u.id = :id")
    int updateBootInstanceStatusById(@Param("id") Long id, @Param("status") Integer status);

    /**
     * 更新下次执行时间和状态
     * @param id
     * @param status
     * @return
     */
    @Modifying
    @Query("UPDATE BootInstance u SET u.status = :status,u.nextExecutionTime = :nextExecutionTime WHERE u.id = :id")
    int updateBootInstanceStatusAndNextExecutionTimeById(@Param("id") Long id, @Param("status") Integer status,@Param("nextExecutionTime") Timestamp nextExecutionTime);


    @Modifying
    @Query("UPDATE BootInstance u SET u.status = :status,u.publicIp = :publicIp,u.successCount = 1 WHERE u.id = :id")
    int updateBootInstanceStatusAndIpById(@Param("id") Long id, @Param("status") Integer status,@Param("publicIp") String publicIp);

    /**
    * @Description: 抢机次数+1
    * @Param: [java.lang.Long, java.lang.Integer, java.lang.String]
    * @return: int
    * @Author doubleDimple
    * @Date: 2/16/25 9:48 AM
    */
    @Modifying
    @Query("UPDATE BootInstance u SET u.addCount = u.addCount + 1 WHERE u.id = :id")
    int incAddCount(@Param("id") Long id);

    @Query("SELECT t FROM BootInstance t WHERE t.status = 1 AND t.nextExecutionTime <= :currentTime")
    List<BootInstance> findTasksToExecute(@Param("currentTime")Timestamp currentTime);

    /**
     * 查询到期任务（支持分页）
     * V2版本使用：简单查询，不做去重
     */
    @Query("SELECT b FROM BootInstance b " +
            "WHERE b.nextExecutionTime <= :currentTime " +
            "AND b.status = 1 " +
            "ORDER BY b.nextExecutionTime ASC")
    List<BootInstance> findTasksToExecute(
            @Param("currentTime") Timestamp currentTime,
            Pageable pageable
    );

    @Query(value = "SELECT * FROM BOOT_INSTANCE " +
            "WHERE next_execution_time <= :currentTime " +
            "AND status = 1 " +
            "ORDER BY next_execution_time ASC " +
            "LIMIT :limit",
            nativeQuery = true)
    List<BootInstance> findTasksToExecute(
            @Param("currentTime") Timestamp currentTime,
            @Param("limit") int limit);


    /**
    * @Description: 查询状态为1的
    * @Param: [java.sql.Timestamp]
    * @return: java.util.List<com.doubledimple.ociserver.domain.BootInstance>
    * @Author doubleDimple
    * @Date: 12/29/24 3:00 PM
    */
    @Query("SELECT t FROM BootInstance t WHERE t.status = 1")
    List<BootInstance> findTasks();



    /**
     * 查询每个租户每种架构类型中状态为1(开机中)的一台抢机任务
     * 不考虑创建时间的先后顺序，如果有多个匹配的实例，返回ID最小的一个
     */
    @Query(value = "SELECT bi.* FROM boot_instance bi " +
            "LEFT JOIN tenant t ON bi.tenant_id = t.id " +
            "WHERE bi.status = 1 " +  // 1表示开机中
            "AND bi.id IN (" +
            "  SELECT MIN(bi2.id) FROM boot_instance bi2 " +
            "  LEFT JOIN tenant t2 ON bi2.tenant_id = t2.id " +
            "  WHERE bi2.status = 1 " +
            "  GROUP BY bi2.tenant_id, bi2.architecture, t2.region" +
            ")", nativeQuery = true)
    List<BootInstance> findTasks2();

    /**
     * 根据租户ID、区域和架构查找下一个待执行任务
     */
    @Query(value = "SELECT bi.* FROM BOOT_INSTANCE bi " +
            "LEFT JOIN tenant t ON bi.tenant_id = t.id " +
            "WHERE bi.status = 1 " +  // 1表示开机中
            "AND t.tenancy = :tenancy " +
            "AND t.region IN (:regions) " +
            "AND bi.architecture = :architecture " +
            "AND bi.id NOT IN (:currentBootId) " +  // 排除当前正在处理的实例
            "ORDER BY bi.id ASC " +
            "LIMIT 1", nativeQuery = true)
    BootInstance findNextTaskByTenantRegionArchitectureExcludingCurrent(
            @Param("tenancy") String tenancy,
            @Param("regions") List<String> regions,
            @Param("architecture") String architecture,
            @Param("currentBootId") Long currentBootId);


    long countByStatus(Integer status);


    /**
    * @Description: 总的抢机次数求和
    * @Param: []
    * @return: java.lang.Integer
    * @Author doubleDimple
    * @Date: 2/16/25 10:03 AM
    */
    @Query("SELECT COALESCE(SUM(b.addCount), 0) FROM BootInstance b")
    long sumAddCount();


    /**
    * @Description: 成功次数求和
    * @Param: []
    * @return: long
    * @Author doubleDimple
    * @Date: 2/16/25 10:05 AM
    */
    @Query("SELECT COALESCE(SUM(b.successCount), 0) FROM BootInstance b")
    long sumSuccessCount();


    /**
    * 根据bootId查询开机中的记录
    */
    @Query("SELECT t FROM BootInstance t WHERE t.status = 1 AND t.bootId = :bootId")
    List<BootInstance> findTasksRunning(@Param("bootId")String bootId);

    @Query("SELECT t FROM BootInstance t WHERE t.bootId = :bootId")
    BootInstance queryBootInstanceById(@Param("bootId")String bootId);

    Page<BootInstance> findByTenantId(Long tenantId, Pageable pageable);

    @Query("SELECT COUNT(b) FROM BootInstance b WHERE b.status = 1 AND b.tenantId = :tenantId")
    int countRunningTasksByTenantId(@Param("tenantId") Long tenantId);


    @Modifying
    @Query(value = "UPDATE BOOT_INSTANCE SET status = :status, public_ip = :publicIp, success_count = 1 " +
            "WHERE id = :id AND status <> :status",
            nativeQuery = true)
    int updateBootInstanceStatusAndIpIfNotEqual(@Param("id") Long id,
                                                @Param("status") int status,
                                                @Param("publicIp") String publicIp);

    @Query(value = "SELECT b1.id, b1.version, b1.boot_id, b1.tenant_id, b1.ocpu, " +
            "b1.memory, b1.disk, b1.loop_time, b1.instance_count, b1.status, " +
            "b1.architecture, b1.root_password, b1.public_ip, b1.next_execution_time, " +
            "b2.record_count as add_count, " +
            "b2.total_count as totalCount, " +
            "b2.fail_count as fail_count, " +
            "b1.success_count, b1.remark, b1.created_at, b1.updated_at, b1.cloud_type, " +
            "b2.total_current_attempt_count as current_attempt_count, " +
            "b2.total_yesterday_attempt_count as yesterday_attempt_count, " +
            "b1.reset_today_flag, b1.last_reset_date, " +
            "b1.image_id, b1.operating_system," +
            "b1.data_gap," +
            "b1.fail_count," +
            "b1.notify_flag," +
            "b1.operating_system_version " +
            "FROM BOOT_INSTANCE b1 " +
            "INNER JOIN (" +
            "    SELECT tenant_id, architecture, MIN(id) as min_id, " +
            "           COUNT(*) as record_count, " +
            "           SUM(fail_count) as fail_count, " +
            "           SUM(add_count) as total_count, " +
            "           SUM(current_attempt_count) as total_current_attempt_count, " +
            "           SUM(yesterday_attempt_count) as total_yesterday_attempt_count " +
            "    FROM BOOT_INSTANCE " +
            "    WHERE (:tenantId IS NULL OR tenant_id = :tenantId) " +
            "    GROUP BY tenant_id, architecture" +
            ") b2 ON b1.id = b2.min_id " +
            "ORDER BY b1.tenant_id, b1.architecture",
            countQuery = "SELECT COUNT(*) FROM (" +
                    "SELECT tenant_id, architecture " +
                    "FROM BOOT_INSTANCE " +
                    "WHERE (:tenantId IS NULL OR tenant_id = :tenantId) " +
                    "GROUP BY tenant_id, architecture) as grouped",
            nativeQuery = true)
    Page<BootInstance> findAllGroupedWithSumAddCount(@Param("tenantId") Long tenantId, Pageable pageable);



    //关联查询
    @Query(value = "SELECT b.* " +
            "FROM BOOT_INSTANCE b " +
            "LEFT JOIN TENANT t ON b.tenant_id = t.id " +
            "WHERE (:tenantId IS NULL OR b.tenant_id = :tenantId) " +
            "ORDER BY b.created_at DESC",
            countQuery = "SELECT COUNT(*) FROM BOOT_INSTANCE b " +
                    "WHERE (:tenantId IS NULL OR b.tenant_id = :tenantId)",
            nativeQuery = true)
    Page<BootInstance> findAllWithTenantInfo(@Param("tenantId") Long tenantId, Pageable pageable);


    List<BootInstance> findByTenantIdAndArchitectureOrderByCreatedAtDesc(Long tenantId, String architecture);
    @Query("SELECT COUNT(b) > 0 FROM BootInstance b WHERE b.tenantId = :tenantId AND b.status = 1")
    boolean existsRunningTaskByTenantId(@Param("tenantId") Long tenantId);

    @Query("SELECT COUNT(b) FROM BootInstance b WHERE b.tenantId = :tenantId AND b.architecture = :architecture AND b.status = 1")
    long existsRunningTaskByTenantIdAndArchitecture(
            @Param("tenantId") Long tenantId,
            @Param("architecture") String architecture
    );

    @Query("SELECT COALESCE(SUM(b.failCount), 0) FROM BootInstance b")
    long sumFailCount();

    @Modifying
    @Query("UPDATE BootInstance u SET u.failCount = 0")
    @Transactional
    void batchInitFailCount();


    @Modifying
    @Transactional
    @Query("UPDATE BootInstance b SET b.yesterdayAttemptCount = b.currentAttemptCount, " +
            "b.currentAttemptCount = 0, b.lastResetDate = :today, b.resetTodayFlag = true")
    void resetAllDailyCounts(@Param("today") java.time.LocalDate today);

    @Modifying
    @Transactional
    @Query("update BootInstance b set b.status = 2, b.updatedAt = CURRENT_TIMESTAMP where b.id = :id")
    void markStatusAsSuccess(@Param("id") Long id);

    @Modifying
    @Transactional
    @Query("update BootInstance b set b.failCount = b.failCount + 1, b.updatedAt = CURRENT_TIMESTAMP where b.id = :id")
    void incrementFailCount(@Param("id") Long id);

    @Modifying
    @Transactional
    @Query(value = "UPDATE boot_instance SET notify_flag = 'YES' " +
            "WHERE id = :id AND notify_flag = 'NO'", nativeQuery = true)
    int markNotificationAsSent(@Param("id") Long id);
}
