package com.chandangs.echo_native

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class RepostFilterTest {
    @Test
    fun sameKeyAndContentIsARepostHowEverLater() {
        val f = RepostFilter()
        assertFalse(f.isRepost("0|com.app|1|null|10", "Your order shipped"))
        assertTrue(f.isRepost("0|com.app|1|null|10", "Your order shipped"))
        assertTrue(f.isRepost("0|com.app|1|null|10", "Your order shipped"))
    }

    @Test
    fun changedContentUnderTheSameKeyIsNews() {
        val f = RepostFilter()
        assertFalse(f.isRepost("k", "1 new email"))
        assertFalse(f.isRepost("k", "2 new emails"))
        assertTrue(f.isRepost("k", "2 new emails"))
    }

    @Test
    fun sameTextUnderAnotherKeyIsNews() {
        val f = RepostFilter()
        assertFalse(f.isRepost("a", "Payment received"))
        assertFalse(f.isRepost("b", "Payment received"))
    }

    @Test
    fun forgottenOnceRemoved() {
        val f = RepostFilter()
        assertFalse(f.isRepost("k", "Time to practise"))
        f.forget("k")
        assertFalse(f.isRepost("k", "Time to practise"))
    }

    @Test
    fun remembersOnlyTheMostRecentKeys() {
        val f = RepostFilter(capacity = 2)
        f.isRepost("a", "x")
        f.isRepost("b", "x")
        f.isRepost("c", "x")
        assertFalse(f.isRepost("a", "x"))
        assertTrue(f.isRepost("c", "x"))
    }
}
