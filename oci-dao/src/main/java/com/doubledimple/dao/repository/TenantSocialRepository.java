package com.doubledimple.dao.repository;

import com.doubledimple.dao.entity.TenantSocial;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.stereotype.Repository;

import java.util.List;
import java.util.Optional;

@Repository
public interface TenantSocialRepository extends JpaRepository<TenantSocial, Long> {

    /**
     * 根据租户ID查找该租户下所有的社交登录配置
     * @param tenantId 租户ID
     * @return 配置列表
     */
    List<TenantSocial> findByTenantId(Long tenantId);

    /**
     * 根据 tenancy (OCID或租户标识) 查找配置
     * @param tenancy 租户标识
     * @return 配置列表
     */
    List<TenantSocial> findByTenancy(String tenancy);

    /**
     * 精确查找：查询某个租户下，特定社交平台（如 Google）的配置
     * 用于判断是否需要执行 update 还是 create
     * * @param tenantId 租户ID
     * @param socialTypeStr 社交类型 (对应 SocialType 枚举的字符串，如 "Google")
     * @return Optional<TenantSocial>
     */
    Optional<TenantSocial> findByTenantIdAndSocialTypeStr(Long tenantId, String socialTypeStr);

    /**
     * 检查某个租户是否已经配置了某种社交登录
     * @param tenantId 租户ID
     * @param socialTypeStr 社交类型
     * @return true/false
     */
    boolean existsByTenantIdAndSocialTypeStr(Long tenantId, String socialTypeStr);

    //根据cloud type查询
    List<TenantSocial> findByCloudType(int cloudType);

}
