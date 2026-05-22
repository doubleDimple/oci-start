package com.doubledimple.ocicommon.enums;

import lombok.Data;
import lombok.Setter;
import lombok.Value;

public enum OperatorEnum {

    //telecom unicom  mobile

    TELECOM("telecom","电信"),
    UNICOM("unicom","联通"),
    MOBILE("mobile","移动");

    private final String type;
    private final String name;
    OperatorEnum(String type,String name) {
        this.type = type;
        this.name = name;
    }

    public String getType() {
        return type;
    }

    public String getName() {
        return name;
    }
}
