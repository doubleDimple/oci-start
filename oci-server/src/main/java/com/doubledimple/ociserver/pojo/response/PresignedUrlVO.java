package com.doubledimple.ociserver.pojo.response;

import lombok.Builder;
import lombok.Data;

@Data
@Builder
public class PresignedUrlVO {

    private String url;
}
