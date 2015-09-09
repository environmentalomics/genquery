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

CREATE TABLE query_def (
    query_id integer NOT NULL,
    title character varying(80) NOT NULL,
    category character varying(80) NOT NULL,
    long_label text,
    hide boolean DEFAULT false NOT NULL,
    icon_index integer,
    column_head text,
    query_body text,
    query_url text,
    export_formats text
) WITHOUT OIDS;

--
-- TOC entry 4 (OID 4556267)
-- Name: pk_query_def; Type: CONSTRAINT; Schema: public; Owner: tbooth
--

ALTER TABLE ONLY query_def
    ADD CONSTRAINT pk_query_def PRIMARY KEY (query_id);

--
-- TOC entry 3 (OID 4556269)
-- Name: query_param; Type: TABLE; Schema: public; Owner: tbooth
--

CREATE TABLE query_param (
    query_id integer NOT NULL,
    param_no integer NOT NULL,
    param_type character varying(10) NOT NULL,
    param_name character varying(20),
    param_text text,
    menu_query text,
    suppress_all boolean
) WITHOUT OIDS;


--
-- TOC entry 4 (OID 4556274)
-- Name: pk_query_param; Type: CONSTRAINT; Schema: public; Owner: tbooth
--

ALTER TABLE ONLY query_param
    ADD CONSTRAINT pk_query_param PRIMARY KEY (query_id, param_no);

--
-- TOC entry 3 (OID 4574864)
-- Name: query_linkout; Type: TABLE; Schema: genquery; Owner: tbooth
--

-- This is obsolete and should be removed:

CREATE TABLE query_linkout (
    query_id integer NOT NULL,
    url text NOT NULL,
    label text,
    name character varying(20) NOT NULL,
    key_column character varying(20) NOT NULL,
    pack boolean DEFAULT false NOT NULL
) WITHOUT OIDS;

--
-- TOC entry 4 (OID 4574870)
-- Name: pk_query_linkout; Type: CONSTRAINT; Schema: genquery; Owner: tbooth
--

ALTER TABLE ONLY query_linkout
    ADD CONSTRAINT pk_query_linkout PRIMARY KEY (query_id, name);


