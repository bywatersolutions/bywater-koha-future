ALTER TABLE reserves ADD printed BOOLEAN NULL AFTER suspend_until;
ALTER TABLE old_reserves ADD printed BOOLEAN NULL AFTER suspend_until;

INSERT INTO  `letter` (
    `module` ,
    `code` ,
    `branchcode` ,
    `name` ,
    `is_html` ,
    `title` ,
    `content`
    )
    VALUES (
    'reserves',  'HOLD_PLACED_PRINT',  '',  'Hold Placed ( Auto-Print )',  '0',  'Hold Placed ( Auto-Print )',  'Hold to pull at <<branches.branchname>>

    For <<borrowers.firstname>> <<borrowers.surname>> ( <<borrowers.cardnumber>> )

    <<biblio.title>> by <<biblio.author>>'
);
