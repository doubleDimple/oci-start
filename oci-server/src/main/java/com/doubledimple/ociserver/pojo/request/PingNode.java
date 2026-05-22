package com.doubledimple.ociserver.pojo.request;

import lombok.Data;

/**
 * @version 1.0.0
 * @ClassName PingNode
 * @Description TODO
 * @Author doubleDimple
 * @Date 2024-12-28 13:01
 */
@Data
public class PingNode {
    private String nodeCode;
    private String nodeName;
    private String nodeId;
    private String area;

    public PingNode(String nodeCode, String nodeName, String nodeId, String area) {
        this.nodeCode = nodeCode;
        this.nodeName = nodeName;
        this.nodeId = nodeId;
        this.area = area;
    }
}
