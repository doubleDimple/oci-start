package com.doubledimple.ociserver.config.exception;

import com.doubledimple.ocicommon.param.ApiResponse;
import com.oracle.bmc.model.BmcException;
import lombok.extern.slf4j.Slf4j;

import static com.doubledimple.ociserver.config.exception.ErrorCode.LIMIT_EXCEEDED;
import static com.doubledimple.ociserver.config.exception.ErrorCode.NOT_AUTH;
import static com.doubledimple.ociserver.config.exception.ErrorCode.NOT_AUTH_NOT_FUND;

/**
 * @author doubleDimple
 * @date 2024:10:04日 21:57
 */
@Slf4j
public class OciExceptionFactory {

    public static OciException createException(ErrorCode errorCode) {
        throw new OciException(errorCode);
    }

    public static ApiResponse buildException(Exception e) {
        if (e instanceof BmcException){
            BmcException error = (BmcException) e;
            if (error.getStatusCode() == 401 && error.getMessage().contains(NOT_AUTH.getErrorType())){
                log.error("resource execute fail: {}", NOT_AUTH.getMessage());
                return ApiResponse.error("资源操作失败,原因为: "+NOT_AUTH.getMessage());
            }else if (error.getStatusCode() == 404 && error.getMessage().contains(NOT_AUTH_NOT_FUND.getErrorType())){
                log.error("resource execute fail: {}", NOT_AUTH.getMessage());
                return ApiResponse.error("资源操作失败,原因为: "+NOT_AUTH.getMessage());
            }else if (error.getMessage().contains(LIMIT_EXCEEDED.getErrorType()) && error.getStatusCode() == LIMIT_EXCEEDED.getCode()){
                log.error("resource execute fail: {}", LIMIT_EXCEEDED.getMessage());
                return ApiResponse.error("资源操作失败,原因为: "+LIMIT_EXCEEDED.getMessage());
            } else {
                return ApiResponse.error("资源操作失败,原因为: "+error.getMessage());
            }
        }else{
            return ApiResponse.error("资源操作失败,原因为: "+e.getMessage());
        }
    }
}
