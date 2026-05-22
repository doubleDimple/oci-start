package com.doubledimple.ocicommon.bark.enums;

import lombok.Getter;
import lombok.RequiredArgsConstructor;

@Getter
@RequiredArgsConstructor
public enum SoundEnum {
    /**
     * gotosleep.caf
     */
    GOTOSLEEP("gotosleep.caf"),
    /**
     * alarm.caf
     */
    PAYMENTSUCCESS("paymentsuccess.caf"),
    SHAKE("shake.caf"),
    ALARM("alarm.caf"),
    BLOOM("bloom.caf"),
    SHERWOODFOREST("sherwoodforest.caf"),
    HEALTHNOTIFICATION("healthnotification.caf"),
    CALYPSO("calypso.caf"),
    DESCENT("descent.caf"),
    LADDER("ladder.caf"),
    TIPTOES("tiptoes.caf"),
    FANFARE("fanfare.caf"),
    BIRDSONG("birdsong.caf"),
    TYPEWRITERS("typewriters.caf"),
    ANTICIPATE("anticipate.caf"),
    CHOO("choo.caf"),
    GLASS("glass.caf"),
    TELEGRAPH("telegraph.caf"),
    MULTIWAYINVITATION("multiwayinvitation.caf"),
    NEWMAIL("newmail.caf"),
    UPDATE("update.caf"),
    MINUET("minuet.caf"),
    SUSPENSE("suspense.caf"),
    MAILSENT("mailsent.caf"),
    NOIR("noir.caf"),
    CHIME("chime.caf"),
    SPELL("spell.caf"),
    ELECTRONIC("electronic.caf"),
    BELL("bell.caf"),
    HORN("horn.caf"),
    NEWSFLASH("newsflash.caf");


    private final String soundName;


}
