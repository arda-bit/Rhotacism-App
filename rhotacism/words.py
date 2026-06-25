from enum import Enum


class WordLevel(str, Enum):
    INITIAL = "initial"
    MEDIAL  = "medial"
    FINAL   = "final"
    CLUSTER = "cluster"


WORD_LISTS: dict[WordLevel, list[str]] = {
    WordLevel.INITIAL: ["red", "run", "rabbit", "rain", "robot", "ring", "river", "road"],
    WordLevel.MEDIAL:  ["very", "carry", "forest", "orange", "around", "parrot"],
    WordLevel.FINAL:   ["car", "far", "floor", "door", "four", "more"],
    WordLevel.CLUSTER: ["green", "brown", "three", "bring", "friend", "dress"],
}
