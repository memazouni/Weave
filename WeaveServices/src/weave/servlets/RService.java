/* ***** BEGIN LICENSE BLOCK *****
 *
 * This file is part of Weave.
 *
 * The Initial Developer of Weave is the Institute for Visualization
 * and Perception Research at the University of Massachusetts Lowell.
 * Portions created by the Initial Developer are Copyright (C) 2008-2015
 * the Initial Developer. All Rights Reserved.
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at http://mozilla.org/MPL/2.0/.
 * 
 * ***** END LICENSE BLOCK ***** */

package weave.servlets;

import java.rmi.RemoteException;

import javax.servlet.ServletConfig;
import javax.servlet.ServletException;

import weave.beans.ClassDiscriminationResult;
import weave.beans.HierarchicalClusteringResult;
import weave.beans.LinearRegressionResult;
import weave.beans.RResult;
import weave.config.WeaveConfig;
import weave.config.WeaveContextParams;
import weave.utils.Strings;

public class RService extends WeaveServlet
{
	private static final long serialVersionUID = 1L;

	public RService()
	{
	}

	private static Process rProcess = null;
	
	public void init(ServletConfig config) throws ServletException
	{
		super.init(config);
		WeaveContextParams wcp = WeaveContextParams.getInstance(config.getServletContext());
		WeaveConfig.initWeaveConfig(wcp);
		docrootPath = wcp.getDocrootPath();
		uploadPath = wcp.getUploadPath();
		rServePath = wcp.getRServePath();
		startRServe();
	}
	
	public void destroy()
	{
		try {
			if (rProcess != null)
				rProcess.destroy();
		} finally {
			super.destroy();
		}
	}

	private String docrootPath = "";
	protected String uploadPath = "";
	private String rServePath = "";
	
	enum ServiceType { JRI, RSERVE; }
	private static ServiceType serviceType = ServiceType.JRI;
	
	public boolean checkforJRIService()throws Exception
	{
	    boolean jriStatus;
	
	    try
		{
			if(RServiceUsingJRI.getREngine() != null)
				jriStatus = true;
			else
				jriStatus = false;
		}
		//if JRI not present
		catch (RServiceUsingJRI.JRIConnectionException e)
		{
			e.printStackTrace();
			jriStatus = false;
		}
		
		return jriStatus;
	}
	
	// this functions makes a command line call on the server machine.
	// the command executed starts the Rserve on windows or unix
	// On windows: the rServePath needs to be given in the configuration file
	// On mac: the command R CMD RServe needs to work http://dev.mygrid.org.uk/blog/?p=34
	private void startRServe()
	{
		if (rProcess == null && !Strings.isEmpty(rServePath))
		{
			if (System.getProperty("os.name").startsWith("Windows")) 
			{
				try 
				{
					rProcess = Runtime.getRuntime().exec(rServePath);
				}
				catch (Exception e) 
				{
					e.printStackTrace();
				}
			}
			else 
			{
				String[] args = {"R", "CMD", "RServe", "--vanilla"};
				try
				{
					rProcess = Runtime.getRuntime().exec(args);
				}
				catch (Exception e)
				{
					e.printStackTrace();
				}
			}
		}
	}
	
	// this function should stop the Rserve... needs revision
	/*private void stopRServe() throws IOException
	{
		try
		{
			if (rProcess != null )
				rProcess.destroy();
		}
		catch (Exception e)
		{
			e.printStackTrace();
		}
	}*/

	public RResult[] runScript( String[] keys,String[] inputNames, Object[] inputValues, String[] outputNames, String script, String plotScript, boolean showIntermediateResults, boolean showWarnings, boolean useColumnAsList) throws Exception
	{
		Exception exception = null;
		
		// check chosen service first
		ServiceType[] types = ServiceType.values();
		if (serviceType != types[0])
		{
			types[1] = types[0];
			types[0] = serviceType;
		}
		for (ServiceType type : types)
		{
			try
			{
				if (type == ServiceType.RSERVE)
					return RServiceUsingRserve.runScript(docrootPath, inputNames, inputValues, outputNames, script, plotScript, showIntermediateResults, showWarnings);
				
				// this crashes Tomcat
				if (type == ServiceType.JRI)
					return RServiceUsingJRI.runScript( docrootPath, keys, inputNames, inputValues, outputNames, script, plotScript, showIntermediateResults, showWarnings, useColumnAsList);
				
			}
			catch (RServiceUsingJRI.JRIConnectionException e)
			{
				e.printStackTrace();
				// remember exception associated with chosen service
				// alternate for next time
				if (type == serviceType)
					exception = e;
				else
					serviceType = type;
			}
			catch (RServiceUsingRserve.RserveConnectionException e)
			{
				e.printStackTrace();
				// remember exception associated with chosen service
				// alternate for next time
				if (type == serviceType)
					exception = e;
				else
					serviceType = type;
			}
		}
		throw new RemoteException("Unable to connect to RServe & Unable to initialize REngine", exception);
	}
	
	
	public LinearRegressionResult linearRegression(String method, double[] dataX, double[] dataY, int polynomialDegree) throws RemoteException
	{
		return RServiceUsingRserve.linearRegression( docrootPath, method, dataX, dataY, polynomialDegree);
	}
	
	public ClassDiscriminationResult doClassDiscrimintation(double[] dataX, double[] dataY, boolean flag) throws RemoteException
	{
		return RServiceUsingRserve.doClassDiscrimination(docrootPath, dataX, dataY, flag);
	}
	
	public Object normalize(Object[][] data) throws RemoteException
	{
		return RServiceUsingRserve.normalize(docrootPath, data);
	}
	public RResult[] kMeansClustering(Object[][] inputValues, boolean showWarnings,int numberOfClusters, int iterations) throws Exception
	{
		
		//return RServiceUsingRserve.kMeansClustering( docrootPath, dataX, dataY, numberOfClusters);
		return RServiceUsingRserve.kMeansClustering(inputValues, showWarnings,numberOfClusters, iterations);
	}

	public HierarchicalClusteringResult hierarchicalClustering(double[] dataX, double[] dataY) throws RemoteException
	{
		return RServiceUsingRserve.hierarchicalClustering( docrootPath, dataX, dataY);
	}

	public RResult[] handlingMissingData(String[] inputNames, Object[][] inputValues, String[] outputNames, boolean showIntermediateResults, boolean showWarnings, boolean completeProcess) throws Exception
	{
		return RServiceUsingRserve.handlingMissingData(inputNames, inputValues, outputNames,showIntermediateResults, showWarnings, completeProcess);
	}
}
