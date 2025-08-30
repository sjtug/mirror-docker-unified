import dataclasses as dc

INDENT_CNT = 4


@dc.dataclass
class Node:
    name: str = ""
    children: list["Node"] = dc.field(default_factory=list)
    comment: str = ""

    def __str__(self, level: int = 0):
        if self.name == "" and len(self.children) == 0:
            return ""
        elif self.name == "":
            return "\n\n".join([child.__str__(level=level) for child in self.children])
        elif len(self.children) == 0:
            lines = self.name.split("\n")
            return (
                "\n".join([" " * (level * INDENT_CNT) + line for line in lines])
                + self.comment_str()
            )
        else:
            children_str = "\n".join(
                [child.__str__(level=level + 1) for child in self.children]
            )
            return (
                " " * (level * INDENT_CNT)
                + self.name
                + " {"
                + self.comment_str()
                + "\n"
                + children_str
                + "\n"
                + " " * (level * INDENT_CNT)
                + "}"
            )

    def comment_str(self):
        return "" if len(self.comment) == 0 else f"  # {self.comment}"


BLANK_NODE = Node()
