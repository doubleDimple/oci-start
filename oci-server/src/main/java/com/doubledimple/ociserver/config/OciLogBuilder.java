package com.doubledimple.ociserver.config;

import com.doubledimple.dao.entity.BootInstance;
import com.doubledimple.dao.repository.BootInstanceRepository;
import com.doubledimple.ociserver.config.exception.OciExceptionFactory;
import com.doubledimple.ociserver.pojo.domain.dto.OracleInstanceDetail;
import com.doubledimple.ociserver.pojo.domain.dto.User;
import com.doubledimple.ociserver.service.BootInstanceService;
import com.oracle.bmc.model.BmcException;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;

import javax.annotation.Resource;
import java.util.Optional;

import static com.doubledimple.ociserver.config.exception.ErrorCode.CAPACITY;
import static com.doubledimple.ociserver.config.exception.ErrorCode.CAPACITY_HOST;
import static com.doubledimple.ociserver.config.exception.ErrorCode.DISK_SIZE_EXCEEDED;
import static com.doubledimple.ociserver.config.exception.ErrorCode.LIMIT_EXCEEDED;
import static com.doubledimple.ociserver.config.exception.ErrorCode.NOT_AUTH;
import static com.doubledimple.ociserver.config.exception.ErrorCode.NOT_AUTH_NOT_FUND;
import static com.doubledimple.ociserver.config.exception.ErrorCode.TOO_MANY_REQUESTS;

/**
 * @version 1.0.0
 * @ClassName OciErrorBuilder
 * @Description TODO
 * @Author doubleDimple
 * @Date 2025-11-22 11:11
 */
@Service
@Slf4j
public class OciLogBuilder {

    @Resource
    private BootInstanceRepository bootInstanceRepository;

    @Resource
    private BootInstanceService bootInstanceService;



    /**
    * @Description: 开机日志异常
    * @Param: [long, java.lang.String, int, com.doubledimple.ociserver.pojo.domain.dto.User, boolean, java.lang.Exception, com.doubledimple.ociserver.pojo.domain.dto.OracleInstanceDetail]
    * @return: com.doubledimple.ociserver.pojo.domain.dto.OracleInstanceDetail
    * @Author: doubleDImple
    * @Date: 4/1/26 9:07 AM
    */
    public OracleInstanceDetail buildOpenBootException(long count, String availablityDomainName, int size, User user, boolean instanceCreated, Exception e, OracleInstanceDetail oracleInstanceDetail) {
        if (instanceCreated) {
            log.warn("[TaskId={}] 实例已创建成功，但后续处理出现异常: {}", user.getBootId(), e.getMessage(), e);
            // 不重抛异常
            return oracleInstanceDetail;
        }
        if (e instanceof BmcException) {
            BmcException error = (BmcException) e;
            if (error.getStatusCode() == 500 &&
                    (error.getMessage().contains(CAPACITY.getErrorType()) || error.getMessage().contains(CAPACITY_HOST.getErrorType()))) {
                if (log.isDebugEnabled()){
                    log.info("");
                    log.info("<=============================>");
                    log.info("[TaskId={}] 用户:{}当前区域容量不足 {} 换另一个可用性区域继续执行", user.getBootId(), user.getUserName(),CAPACITY.getMessage());
                    log.info("<=============================>");
                    log.info("");
                }
                size--;
                if (size <= 0) {
                    if (log.isDebugEnabled()){
                        log.warn("[TaskId={}] 用户:[{}]的区域:[{}]的架构:[{}]未完成开机,具体原因为:[{}]", user.getBootId(), user.getUserName(),user.getRegion(),user.getArchitecture(),e.getMessage());
                    }
                    log.info("[TaskId={}] 用户:[{}]的区域:[{}]的架构:[{}]未完成开机,已执行抢机次数为:[{}],原因为:{},将在:[{}]秒后重试...", user.getBootId(), user.getUserName(),user.getRegion(),user.getArchitecture(),count,CAPACITY.getMessage(),user.getInterval());
                }
            } else if (error.getStatusCode() == 400 ) {
                String message = error.getMessage();
                if (message.contains(LIMIT_EXCEEDED.getErrorType())){
                    log.warn("[TaskId={}] 用户:[{}]无法创建 always free 机器,区域:{}配额已经超过免费额度,将停止开机", user.getBootId(), user.getUserName(),availablityDomainName);
                    doStopInstance(user.getBootId(),LIMIT_EXCEEDED.getMessage());
                    OciExceptionFactory.createException(LIMIT_EXCEEDED);
                }else if (error.getServiceCode().equals("QuotaExceeded")){
                    if (message.contains("bootVolumeQuota")){
                        log.warn("[TaskId={}] 用户:[{}]无法在区域:{}创建 always free 机器磁盘超出限制", user.getBootId(), user.getUserName(),availablityDomainName);
                        doStopInstance(user.getBootId(),DISK_SIZE_EXCEEDED.getMessage());
                        OciExceptionFactory.createException(DISK_SIZE_EXCEEDED);
                    }
                }
            } else if (error.getStatusCode() == 401 && error.getMessage().contains(NOT_AUTH.getErrorType())){
                log.warn("[TaskId={}] 用户:[{}]无法创建资源.api无权限", user.getBootId(), user.getUserName());
                doStopInstance(user.getBootId(),NOT_AUTH.getMessage());
                OciExceptionFactory.createException(NOT_AUTH);
            }else if (error.getStatusCode() == 404 && error.getMessage().contains(NOT_AUTH_NOT_FUND.getErrorType())){
                log.warn("[TaskId={}] 用户:[{}]无法创建资源.api无权限或者资源不存在,继续执行", user.getBootId(), user.getUserName());
                //todo 停止抢机(这里暂时不要停止抢机,有可能是无资源)
                //doStopInstance(user.getBootId(),NOT_AUTH.getMessage());
                //OciExceptionFactory.createException(NOT_AUTH);
            }else if (error.getStatusCode() == 429 && error.getMessage().contains(TOO_MANY_REQUESTS.getErrorType())){
                log.warn("[TaskId={}] 用户:[{}]抢机频率太快", user.getBootId(), user.getUserName());
            }
            else {
                //clearAllDetails(computeClient, virtualNetworkClient, instanceFromBootVolume, instance, networkSecurityGroup, internetGateway, subnet, vcn);
                log.warn("[TaskId={}] 出现未知问题.....原因为:{}", user.getBootId(), e.getMessage());
            }
        } else {
            if (e instanceof IllegalStateException){
                log.warn("[TaskId={}] 当前区域出现,原因为:{}", user.getBootId(), e.getMessage());
            }
            log.warn("[TaskId={}] 用户:{} 当前区域:{} 执行失败,原因:{}", user.getBootId(), user.getUserName(),availablityDomainName,e.getMessage());
        }
        return oracleInstanceDetail;
    }

    //成功开机日志
    public void buildOpenBootSuccess(String format, Object... arguments) {
        log.info(format, arguments);
    }

    //不抛出异常的日志
    public void buildOpenNoThrow(String format, Object... arguments) {
        log.warn(format, arguments);
    }

    public void doStopInstance(Long booId,String reason) {
        Optional<BootInstance> bootInstance1 = bootInstanceRepository.findById(booId);
        BootInstance bootInstance = bootInstance1.get();
        if (bootInstance.getStatus() == 1){
            bootInstanceService.autoStopBoot(bootInstance,reason);
        }
    }
}
