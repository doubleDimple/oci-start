package com.doubledimple.ociserver.pojo.response;

import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

import java.io.Serializable;

/**
 * @version 1.0.0
 * @ClassName OciDbResponse
 * @Description TODO
 * @Author doubleDimple
 * @Date 2025-12-31 17:18
 */
@Data
@Builder
@AllArgsConstructor
@NoArgsConstructor
public class OciDbDetail implements Serializable {

    private String dbName;

    private String dbPassword;

    private String dbUrl;

    private String dbId;
}
