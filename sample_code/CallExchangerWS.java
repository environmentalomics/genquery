/*
 * Created on 17 Sep 2010
 *
 * To change the template for this generated file go to
 * Window&gt;Preferences&gt;Java&gt;Code Generation&gt;Code and Comments
 */

import java.io.File;
import java.io.FileReader;
import java.io.UnsupportedEncodingException;
import java.net.MalformedURLException;
import java.net.URL;
import java.net.URLEncoder;
import java.sql.Connection;
import java.sql.DriverManager;
import java.sql.ResultSetMetaData;
import java.sql.SQLException;

import javax.sql.rowset.WebRowSet;
import com.sun.rowset.WebRowSetImpl;

public class CallExchangerWS {

	String endpoint = "";
	StringBuffer query = new StringBuffer();
	
	WebRowSet wrs = null;
	
	/**
	 * Demonstrates how to make a query against GenQuery
		
	 * @param args - ignored
	 * @throws Exception
	 */
	public static void main(String[] args) throws Exception {
		
		CallExchangerWS caller = new CallExchangerWS();
		
		caller.endpoint = "http://barsukas.nwl.ac.uk/~tbooth/cgi-bin/genquery/gq.cgi";
		
		//Ensure XML output
		caller.addParam("rm", "dl");
		caller.addParam("fmt", "WebRowSet");
		
		//Set database and query
		caller.addParam("0:db_name", "test_barcode");
		caller.addParam("queryname", "Show Users");

		//Add parameters to query
		caller.addParam("qp_INST", "CEH Oxford");
		caller.addParam("qp_ONLYBARCODES", null);
		
		//Make the call
		caller.fetchResult();
		
		System.out.println(caller.resultToTable());
	}
	
	private void addParam(String name, String val)
	{
		try{ if(val != null)
		{
			if(!query.equals("")) query.append(";");
			query.append(URLEncoder.encode(name, "UTF-8"));
			query.append("=");
			query.append(URLEncoder.encode(val, "UTF-8"));
		}} 
		catch (UnsupportedEncodingException e) {
			//This is unpossible!
			throw new Error(e);
		}
	}
	
	private void fetchResult() throws Exception
	{
		URL qURL = new URL(endpoint + '?' + query);
		
		wrs = new WebRowSetImpl();
		wrs.readXml(qURL.openStream());
	}
	
	private String resultToTable() throws SQLException
	{
		StringBuffer result = new StringBuffer("");
		ResultSetMetaData md = wrs.getMetaData();
		
		for(int nn = 1; nn <= md.getColumnCount(); nn++)
		{
			result.append(md.getColumnLabel(nn));
			result.append(nn < md.getColumnCount() ? "," : "\n");
		}
		
		while(wrs.next())
		{
			for(int nn = 1; nn <= md.getColumnCount(); nn++)
			{
				Object val = wrs.getObject(nn);
				result.append(val == null ? "/NULL/" : val);
				result.append(nn < md.getColumnCount() ? "," : "\n");
			}
		}
		
		return result.toString();
	}
}
