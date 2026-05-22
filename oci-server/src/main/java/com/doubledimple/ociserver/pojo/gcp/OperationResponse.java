package com.doubledimple.ociserver.pojo.gcp;

import com.fasterxml.jackson.annotation.JsonIgnoreProperties;
import lombok.Data;

import java.util.Map;

/**
 * GCP操作响应
 */
@Data
@JsonIgnoreProperties(ignoreUnknown = true)
public class OperationResponse {
    private String kind;
    private String id;
    private String name;
    private String zone;
    private String operationType;
    private String targetId;
    private String targetLink;
    private String status;
    private String selfLink;
    private String insertTime;
    private String startTime;
    private String endTime;
    private Integer progress;
    private Error error;
    private Map<String, Object> warnings;
    private String httpErrorStatusCode;
    private String httpErrorMessage;
    private String user;
    private String clientOperationId;

    @Data
    @JsonIgnoreProperties(ignoreUnknown = true)
    public static class Error {
        private Integer code;
        private String message;
        private ErrorItem[] errors;

        @Data
        @JsonIgnoreProperties(ignoreUnknown = true)
        public static class ErrorItem {
            private String code;
            private String message;
            private String location;
        }
    }
}
