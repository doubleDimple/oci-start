package com.doubledimple.ociserver.service;

public interface BanService {


    public boolean banIp(String ip,String reason);

    boolean unbanIp(String ip,String reason);

    boolean unbanIp(String ip, String reason, String operatorName);

    UnbanRecordResult unbanRecord(Long id, String reason, String operatorName);

    enum UnbanRecordResult {
        NOT_FOUND,
        ALREADY_RELEASED,
        RELEASED
    }
}
