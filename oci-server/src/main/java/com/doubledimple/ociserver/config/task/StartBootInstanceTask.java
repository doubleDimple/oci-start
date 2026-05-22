package com.doubledimple.ociserver.config.task;

import cn.hutool.json.JSONUtil;
import com.doubledimple.dao.entity.BootInstance;
import com.doubledimple.dao.repository.TenantRepository;
import com.doubledimple.ociserver.pojo.domain.dto.OracleInstanceDetail;
import com.doubledimple.ociserver.pojo.domain.dto.User;
import com.doubledimple.ociserver.pojo.enums.MessageEnum;
import com.doubledimple.ociserver.service.message.factory.MessageFactory;
import com.doubledimple.ociserver.service.BootTotalInstanceService;
import com.doubledimple.ociserver.service.oracle.OracleCloudService;
import lombok.extern.slf4j.Slf4j;
import org.springframework.context.ApplicationEventPublisher;
import org.springframework.stereotype.Service;

import javax.annotation.Resource;

import static com.doubledimple.ociserver.config.constant.GenPojoUtils.bootPojo;

/**
 * @author doubleDimple
 * @date 2024:10:24日 22:36
 */
@Service
@Slf4j
public class StartBootInstanceTask {

    @Resource
    private TenantRepository tenantRepository;

    @Resource
    OracleCloudService oracleCloudService;

    @Resource
    private BootTotalInstanceService bootTotalInstanceService;

    @Resource
    MessageFactory messageFactory;

    @Resource
    private ApplicationEventPublisher eventPublisher;


    /**
    * @Description: 手动开机逻辑,暂时这样处理吧
    * @Param: [com.doubledimple.ociserver.domain.BootInstance]
    * @return: void
    * @Author doubleDimple
    * @Date: 1/4/25 8:34 AM
    */
    public void doStartInstance(BootInstance bootInstance){
        User user = bootPojo(
                tenantRepository.findById(bootInstance.getTenantId()).get(),
                bootInstance);

        user.setIsRunning(true);
        user.setIsSuccess(false);

        if (log.isDebugEnabled()){
            log.info("");
            log.info("<============================================>");
            log.info("用户:[{}]开始枪机....", user.getUserName());
            log.info("<============================================>");
            log.info("");
        }


        try {
            oracleCloudService.createInstanceData(user);
        } catch (Exception e) {
            log.error("抢机任务执行失败，用户：{}，原因：{}", user.getUserName(), e.getMessage(), e);
        }
    }

    public void doHandlerSuccess(User user,OracleInstanceDetail instanceData ) {
        //修改开机状态,修改ip
        log.info("当前用户:{},创建了实例:{}",user.getUserName(), JSONUtil.toJsonStr(instanceData));
        try {
            sendNotification(user.getUserName(), instanceData);
            bootTotalInstanceService.updatePublicIp(user.getBootId(),2,instanceData.getPublicIp());
        } catch (Exception e) {
            log.error("handler database fail,reason:{}",e.getMessage(),e);
        }
    }

    private void sendNotification(String userName, OracleInstanceDetail instanceData) {
        instanceData.setUserName(userName);
        messageFactory.getType(MessageEnum.TELEGRAM).sendMessage(instanceData);
    }


}
