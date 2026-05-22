package com.doubledimple.ociserver.pojo.response;

import com.doubledimple.ociserver.pojo.request.TrafficAlertDTO;
import lombok.Data;

/**
 * @version 1.0.0
 * @ClassName TrafficAlertResponse
 * @Description TODO
 * @Author doubleDimple
 * @Date 2025-03-13 14:01
 */
@Data
public class TrafficAlertResponse {
    private Boolean success;
    private String message;
    private TrafficAlertDTO data;

    public static TrafficAlertResponse success(TrafficAlertDTO data) {
        TrafficAlertResponse response = new TrafficAlertResponse();
        response.setSuccess(true);
        response.setData(data);
        return response;
    }

    public static TrafficAlertResponse error(String message) {
        TrafficAlertResponse response = new TrafficAlertResponse();
        response.setSuccess(false);
        response.setMessage(message);
        return response;
    }
}
