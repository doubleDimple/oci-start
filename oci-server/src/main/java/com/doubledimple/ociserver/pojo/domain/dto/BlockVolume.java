package com.doubledimple.ociserver.pojo.domain.dto;

import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

/**
 * @author doubleDimple
 * @date 2024:11:03日 15:41
 */
@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class BlockVolume {
    private String id;
    private String displayName;
    private Long sizeInGBs;
}
