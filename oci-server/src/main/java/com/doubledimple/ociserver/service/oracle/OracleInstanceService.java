package com.doubledimple.ociserver.service.oracle;

import com.doubledimple.dao.entity.InstanceDetails;
import com.doubledimple.ociserver.pojo.request.IpSwitchRequest;
import com.doubledimple.ociserver.pojo.request.IpVnicSwitchRequest;
import com.doubledimple.ociserver.pojo.request.SysImageBackupRequest;
import com.doubledimple.ocicommon.param.ApiResponse;
import com.doubledimple.ociserver.pojo.response.InstanceDetailsRes;
import com.doubledimple.ociserver.pojo.response.InstanceTrafficVO;
import com.doubledimple.ociserver.pojo.response.OciGroupResp;
import com.oracle.bmc.auth.AuthenticationDetailsProvider;
import com.oracle.bmc.core.model.Instance;
import org.springframework.data.domain.Page;
import org.springframework.http.ResponseEntity;

import java.util.List;

public interface OracleInstanceService {


    List<Instance> getAllInstances(AuthenticationDetailsProvider provider);

    /**
    * @Description: 按照分页查询所有
    * @Param: [int, int]
    * @return: org.springframework.data.domain.Page<com.doubledimple.ociserver.response.InstanceDetailsRes>
    * @Author doubleDimple
    * @Date: 2/22/25 10:14 AM
    */
    Page<InstanceDetailsRes> getAllInstances(int page, int size,String instanceId);

    /**
    * @Description: 根据tennetid查询
    * @Param: [java.lang.String, int, int]
    * @return: org.springframework.data.domain.Page<com.doubledimple.ociserver.response.InstanceDetailsRes>
    * @Author doubleDimple
    * @Date: 2/22/25 10:15 AM
    */
    public Page<InstanceDetailsRes> getInstancePageByTenantId(String tenantId, int page, int size);


    public ResponseEntity<?> changePublicIp(Long instanceId);

    public ResponseEntity<?> changePublicIp2(Long instanceId);


    public ResponseEntity<?> checkAccountStatus(long tenantId);

    ResponseEntity<?> switchToSpecificIpRange(IpSwitchRequest request);

     String enableOrRefreshIpv6(Long instanceDetailId, boolean forceNewAddress);

     ResponseEntity<?> killInstance(Long instanceDetailId);

    void sendCode(Long instanceDetailId,String code);

    void updateInstanceConfig(String instanceId, Integer cpu, Integer memory);

    boolean updateInstanceName(String instanceId, String newName);

    /**
    * @Description: 扩容
    * @Param: [java.lang.String, java.lang.Long]
    * @return: org.springframework.http.ResponseEntity<?>
    * @Author doubleDimple
    * @Date: 11/26/24 7:12 PM
    */
    ResponseEntity<ApiResponse> handleExpansion(String instanceId, Long bootVolumeSize);

    /**
    * @Description: 引导卷缩容
    * @Param: [java.lang.String, java.lang.Long]
    * @return: org.springframework.http.ResponseEntity<?>
    * @Author doubleDimple
    * @Date: 11/26/24 7:12 PM
    */
    ResponseEntity<ApiResponse> handleShrink(String instanceId, Long bootVolumeSize);


    /**
    * 创建普通用户
    */
    String createOciUser(Long tenantId,String username,String email);

    /**
     * 创建管理员用户
     */
    String createOciAdminUser(Long tenantId,String username,String email,String groupId);


    /**
    * 查询用户组
    */
    public List<OciGroupResp> findGroup(Long tenantId);

    /**
    * @Description: 备注
    * @Param: [java.lang.Long, java.lang.String]
    * @return: void
    * @Author doubleDimple
    * @Date: 2/16/25 10:55 AM
    */
    void updateRemark(Long instanceId, String remark);


    /**
    * 根据实例id查询实例信息
    */
    void getInstanceDetails(List<InstanceTrafficVO> collect);

    /**
    * 停止实例
    */
    void stopInstance(String instanceId, String providerTenantId);

    boolean stopInstanceByInstanceId(String instanceId);

    boolean startInstance(String instanceId);

    InstanceDetails getInstanceByInstanceId(String instanceId);

    void updateInstance(InstanceDetails instance);

    InstanceDetails getInstanceById(Long valueOf);

    /**
    * 系统备份
    */
    ResponseEntity<?> sysImageBackUp(SysImageBackupRequest sysImageBackupRequest);

    /**
    * 指定vnic切换ip
    */
    ResponseEntity<?> switchVnicToSpecificIpRange(IpVnicSwitchRequest ipVnicSwitchRequest);

    ApiResponse enablePing(int cloudType);

    ApiResponse disablePing(int cloudType);

    ApiResponse batchPing(int i);

    /**
     * 从数据库删除实例记录（仅删除本地记录，不操作OCI云端）
     */
    ApiResponse deleteInstanceRecord(Long id);
}
