--
-- XC_MISC
--

-- A function to return a unified data node name given a node identifer 
create or replace function get_unified_node_name(node_ident int) returns varchar language plpgsql as $$
declare
	r pgxc_node%rowtype;
	node int;
	nodenames_query varchar;
begin
	nodenames_query := 'SELECT * FROM pgxc_node  WHERE node_type = ''D'' ORDER BY xc_node_id';

	node := 1;
	for r in execute nodenames_query loop
		if r.node_id = node_ident THEN
			RETURN 'NODE_' || node;
		end if;
		node := node + 1;
	end loop;
	RETURN 'NODE_?';
end;
$$;

-- Test the system column added by XC called xc_node_id, used to find which tuples belong to which data node

select create_table_nodes('t1_misc(a int, b int)', '{1, 2}'::int[], 'modulo(a)', NULL);
insert into t1_misc values(1,11),(2,11),(3,11),(4,22),(5,22),(6,33),(7,44),(8,44);

select get_unified_node_name(xc_node_id),* from t1_misc order by a;

select get_unified_node_name(xc_node_id),* from t1_misc where xc_node_id > 0 order by a;

create table t2_misc(a int , xc_node_id int) distribute by modulo(a);

create table t2_misc(a int , b int) distribute by modulo(xc_node_id);

drop table t1_misc;

-- Test an SQL function with multiple statements in it including a utility statement.

create table my_tab1 (a int);

insert into my_tab1 values(1);

create function f1 () returns setof my_tab1 as $$ create table my_tab2 (a int); select * from my_tab1; $$ language sql;

SET check_function_bodies = false;

create function f1 () returns setof my_tab1 as $$ create table my_tab2 (a int); select * from my_tab1; $$ language sql;

select f1();

SET check_function_bodies = true;

drop function f1();

-- Test pl-pgsql functions containing utility statements

CREATE OR REPLACE FUNCTION test_fun_2() RETURNS SETOF my_tab1 AS '
DECLARE
   t1 my_tab1;
   occ RECORD;
BEGIN
   CREATE TABLE tab4(a int);
   CREATE TABLE tab5(a int);

   FOR occ IN SELECT * FROM my_tab1
   LOOP
     t1.a := occ.a;
     RETURN NEXT t1;
   END LOOP;

   RETURN;
END;' LANGUAGE 'plpgsql';

select test_fun_2();

drop function test_fun_2();

drop table tab4;
drop table tab5;
drop table my_tab1;

-- Test to make sure that the block of
-- INSERT SELECT in case of inserts into a child by selecting from
-- a parent works fine

create table t_11 ( a int, b int);
create table t_22 ( a int, b int);
insert into t_11 values(1,2),(3,4);
insert into t_22 select * from t_11; -- should pass

CREATE TABLE c_11 () INHERITS (t_11);
insert into c_11 select * from t_22; -- should pass
insert into c_11 select * from t_11; -- should fail
insert into c_11 (select * from t_11 union all select * from t_22); -- should fail
insert into c_11 (select * from t_11,t_22); -- should fail
insert into c_11 (select * from t_22 where a in (select a from t_11)); -- should pass
insert into c_11 (select * from t_11 where a in (select a from t_22)); -- should fail
insert into t_11 select * from c_11; -- should pass

-- test to make sure count from a parent table works fine
select count(*) from t_11;

CREATE TABLE grand_parent (code int, population float, altitude int);
INSERT INTO grand_parent VALUES (0, 1.1, 63);
CREATE TABLE my_parent (code int, population float, altitude int);
INSERT INTO my_parent VALUES (1, 2.1, 73);
CREATE TABLE child_11 () INHERITS (my_parent);
CREATE TABLE grand_child () INHERITS (child_11);

INSERT INTO child_11 SELECT * FROM grand_parent; -- should pass
INSERT INTO child_11 SELECT * FROM my_parent; -- should fail
INSERT INTO grand_child SELECT * FROM my_parent; -- should pass
INSERT INTO grand_child SELECT * FROM grand_parent; -- should pass

drop table grand_child;
drop table child_11;
drop table my_parent;
drop table grand_parent;
drop table c_11;
drop table t_22;
drop table t_11;
