package com.doubledimple.ociserver.config.constant;

import cn.hutool.core.util.IdUtil;
import com.doubledimple.dao.entity.BootInstance;
import com.doubledimple.dao.entity.Tenant;
import com.doubledimple.ocicommon.enums.RegionEnum;
import com.doubledimple.ociserver.pojo.domain.dto.User;
import org.apache.commons.lang3.StringUtils;

import static com.doubledimple.ociserver.utils.oracle.OciUtils.DEFAULT_PASSWD;

/**
 * @author doubleDimple
 * @date 2024:10:12日 23:30
 */
public class GenPojoUtils {




    public static User bootPojo(Tenant tenant, BootInstance bootInstance){
        String codeByName = RegionEnum.getRegionCode(tenant.getRegion());
        //String operationSystem = bootInstance.getOperationSystem();
        User user = new User();
        user.setUserId(tenant.getTenantId());
        user.setUserName(tenant.getUserName());
        user.setRegion(tenant.getRegion());
        user.setFingerprint(tenant.getFingerprint());
        user.setTenancy(tenant.getTenancy());
        user.setRegion(codeByName);
        user.setKeyFile(tenant.getKeyFile());
        user.setOcpus(bootInstance.getOcpu());
        user.setMemory(bootInstance.getMemory());
        user.setDisk(Long.valueOf(bootInstance.getDisk()));
        user.setArchitecture(bootInstance.getArchitecture());
        user.setInterval(bootInstance.getLoopTime());
        user.setRootPassword(bootInstance.getRootPassword());
        user.setBootId(bootInstance.getId());
        user.setUniqueStrId(tenant.getUserName());
        user.setId(tenant.getId());

        if (StringUtils.isNotBlank(bootInstance.getImageId())){
            user.setImageId(bootInstance.getImageId());
            user.setOperatingSystem(bootInstance.getOperatingSystem());
            user.setOperatingSystemVersion(bootInstance.getOperatingSystemVersion());
        }

        /*if (StringUtils.isNotBlank(operationSystem)){
            user.setOperationSystem(operationSystem);
        }*/
        return user;
    }

    public static User bootPojo(Tenant tenant,String architecture){
        String codeByName = RegionEnum.getRegionCode(tenant.getRegion());
        User user = new User();
        user.setUserId(tenant.getTenantId());
        user.setUserName(tenant.getUserName());
        user.setRegion(tenant.getRegion());
        user.setFingerprint(tenant.getFingerprint());
        user.setTenancy(tenant.getTenancy());
        user.setRegion(codeByName);
        user.setKeyFile(tenant.getKeyFile());
        user.setOcpus(1F);
        user.setMemory(1F);
        user.setDisk(50L);
        user.setArchitecture(architecture);
        user.setInterval(30);
        user.setRootPassword(DEFAULT_PASSWD);
        user.setBootId(IdUtil.getSnowflakeNextId());
        user.setUniqueStrId(tenant.getUserName());
        user.setId(tenant.getId());
        return user;
    }
}
