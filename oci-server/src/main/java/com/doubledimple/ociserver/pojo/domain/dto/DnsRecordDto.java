package com.doubledimple.ociserver.pojo.domain.dto;

import com.doubledimple.dao.entity.DnsRecord;
import lombok.Data;

import java.util.List;

/**
 * @version 1.0.0
 * @ClassName DnsRecordDto
 * @Description TODO
 * @Author doubleDimple
 * @Date 2025-07-27 12:39
 */
@Data
public class DnsRecordDto {

    List<DnsRecord> dnsRecords;
}
