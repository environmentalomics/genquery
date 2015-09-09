--
-- PostgreSQL database dump
--

SET client_encoding = 'UNICODE';
--SET check_function_bodies = false;

CREATE schema genquery;
SET search_path = genquery;

--
-- TOC entry 3 (OID 4556262)
-- Name: query_def; Type: TABLE; Schema: public; Owner: tbooth
--

CREATE TABLE cat_webquery_def_2 (
    query_id integer NOT NULL,
    title character varying(80) NOT NULL,
    category character varying(80) NOT NULL,
    long_label text,
    hide boolean DEFAULT false NOT NULL,
    icon_index integer,
    column_head text,
    query_body text,
    query_url text
) WITHOUT OIDS;

--
-- TOC entry 4 (OID 4556267)
-- Name: pk_query_def; Type: CONSTRAINT; Schema: public; Owner: tbooth
--

ALTER TABLE ONLY cat_webquery_def_2
    ADD CONSTRAINT pk_query_def PRIMARY KEY (query_id);

--
-- TOC entry 3 (OID 4556269)
-- Name: query_param; Type: TABLE; Schema: public; Owner: tbooth
--

CREATE TABLE cat_webquery_param_2 (
    query_id integer NOT NULL,
    param_no integer NOT NULL,
    param_type character varying(10) NOT NULL,
    param_name character varying(20),
    param_text text,
    menu_query text
) WITHOUT OIDS;


--
-- TOC entry 4 (OID 4556274)
-- Name: pk_query_param; Type: CONSTRAINT; Schema: public; Owner: tbooth
--

ALTER TABLE ONLY cat_webquery_param_2
    ADD CONSTRAINT pk_query_param PRIMARY KEY (query_id, param_no);


