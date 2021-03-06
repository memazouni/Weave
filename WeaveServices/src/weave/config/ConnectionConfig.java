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

package weave.config;

import java.io.File;
import java.io.FileOutputStream;
import java.io.IOException;
import java.net.URL;
import java.rmi.RemoteException;
import java.sql.Connection;
import java.sql.SQLException;
import java.util.Collection;
import java.util.Collections;
import java.util.HashMap;
import java.util.LinkedList;
import java.util.List;
import java.util.Map;
import java.util.Map.Entry;

import javax.xml.xpath.XPath;
import javax.xml.xpath.XPathConstants;
import javax.xml.xpath.XPathFactory;

import org.w3c.dom.Document;
import org.w3c.dom.Element;
import org.w3c.dom.NamedNodeMap;
import org.w3c.dom.Node;
import org.w3c.dom.NodeList;

import weave.utils.CSVParser;
import weave.utils.FileUtils;
import weave.utils.MapUtils;
import weave.utils.ProgressManager;
import weave.utils.SQLUtils;
import weave.utils.Strings;
import weave.utils.XMLUtils;

/**
 * An interface to retrieve strings from a configuration file.
 * 
 * @author Andy Dufilie
 */
public class ConnectionConfig
{
	@SuppressWarnings("serial")
	public static class WeaveAuthenticationException extends RemoteException
	{
		public WeaveAuthenticationException(String explanation)
		{
			super(explanation);
		}
	}
	
	public static final String XML_FILENAME = "sqlconfig.xml";
	public static final String DTD_FILENAME = "sqlconfig.dtd";
	public static final String SQLITE_DB_FILENAME = "weave.db";
	public static final URL DTD_EMBEDDED = ConnectionConfig.class.getResource("/weave/config/" + DTD_FILENAME);
	
	public ConnectionConfig(File file)
	{
		_file = file;
		FileUtils.protect(_file);
	}
	
	private boolean _temporaryDataConfigPermission = false;
	private boolean _oldVersionDetected = false;
	private long _lastMod = 0L;
	private File _file;
	private DatabaseConfigInfo _databaseConfigInfo;
	private Map<String,ConnectionInfo> _connectionInfoMap = new HashMap<String,ConnectionInfo>();
	private Connection _adminConnection = null;
	
	/**
	 * Creates an empty SQLite database file if it doesn't already exist.
	 * This is only used if SQLite is the chosen config storage location.
	 * @return A reference to the SQLite database file.
	 * @throws IOException
	 * /
	private File getSQLiteDatabaseFile() throws IOException
	{
		File f = new File(_file.getParent(), SQLITE_DB_FILENAME);
		f.createNewFile();
		return f;
	}*/
	
	public long getLastModified() throws RemoteException
	{
		_load();
		return _lastMod;
	}
	
	/**
	 * This function must be called before making any modifications to the config.
	 */
	@SuppressWarnings("deprecation")
	public DataConfig initializeNewDataConfig(ProgressManager progress) throws RemoteException
	{
		if (migrationPending())
		{
			try
			{
				DataConfig dataConfig;
				
				synchronized (this)
				{
					// momentarily give DataConfig permission to initialize
					_temporaryDataConfigPermission = true;
					dataConfig = new DataConfig(this);
					_temporaryDataConfigPermission = false;
				}
				
				DeprecatedConfig.migrate(this, dataConfig, progress);
				
				// after everything has successfully been migrated, save under new connection config format
				_oldVersionDetected = false;
				_save();
				return dataConfig;
			}
			finally
			{
				_temporaryDataConfigPermission = false;
			}
		}
		else
		{
			return new DataConfig(this);
		}
	}
	
	public boolean allowDataConfigInitialize() throws RemoteException
	{
		return _temporaryDataConfigPermission || !migrationPending();
	}
	
	public boolean migrationPending() throws RemoteException
	{
		_load();
		return _oldVersionDetected;
	}

	/**
	 * This function gets a connection to the database containing the configuration information. This function will reuse a previously created
	 * Connection if it is still valid.
	 * 
	 * @return A Connection to the SQL database.
	 */
	public Connection getAdminConnection() throws RemoteException, SQLException
	{
		_load();
		
		// if old version is detected, don't run test query
		boolean isValid = _oldVersionDetected ? _adminConnection != null : SQLUtils.connectionIsValid(_adminConnection);
		// use previous connection if still valid
		if (isValid)
			return _adminConnection;
		
		DatabaseConfigInfo dbInfo = _databaseConfigInfo;

		if (dbInfo == null)
			throw new RemoteException("databaseConfig has not been specified.");
		
		if (dbInfo.schema == null || dbInfo.schema.length() == 0)
			throw new RemoteException("databaseConfig schema has not been specified.");
		
		ConnectionInfo connInfo = getConnectionInfo(dbInfo.connection);
		
		if (connInfo == null)
			throw new RemoteException(String.format("Connection named \"%s\" does not exist.", dbInfo.connection));
		
		try
		{
			return _adminConnection = connInfo.getConnection();
		}
		catch (WeaveAuthenticationException e)
		{
			// should not happen
			throw new RemoteException("Unexpected error. Admin connection should not require pass-through authentication.", e);
		}
	}
	
	private void resetAdminConnection()
	{
		SQLUtils.cleanup(_adminConnection);
		_adminConnection = null;
	}
	
	private void _setXMLAttributes(Element tag, Map<String,String> attrs)
	{
		for (Entry<String,String> entry : attrs.entrySet())
			tag.setAttribute(entry.getKey(), entry.getValue());
	}
	
	private Map<String,String> _getXMLAttributes(Node node)
	{
		NamedNodeMap attrs = node.getAttributes();
		Map<String, String> attrMap = new HashMap<String, String>();
		for (int j = 0; j < attrs.getLength(); j++)
		{
			Node attr = attrs.item(j);
			String attrName = attr.getNodeName();
			String attrValue = attr.getTextContent();
			attrMap.put(attrName, attrValue);
		}
		return attrMap;
	}
	
	private void _load() throws RemoteException
	{
		long lastMod = _file.lastModified();
		if (_lastMod != lastMod)
		{
			// if file was deleted since last time, clear all info
			if (!_file.exists())
			{
				_lastMod = 0L;
				_oldVersionDetected = false;
				_connectionInfoMap.clear();
				_databaseConfigInfo = null;
				resetAdminConnection();
				return;
			}
			
			try
			{
				// read file as XML
				Document doc = XMLUtils.getValidatedXMLFromFile(_file);
				XPath xpath = XPathFactory.newInstance().newXPath();
				
				// read all ConnectionInfo
				Map<String,ConnectionInfo> connectionInfoMap = new HashMap<String,ConnectionInfo>();
				NodeList nodes = (NodeList) xpath.evaluate("/sqlConfig/connection", doc, XPathConstants.NODESET);
				for (int i = 0; i < nodes.getLength(); i++)
				{
					ConnectionInfo info = new ConnectionInfo();
					info.copyFrom(_getXMLAttributes(nodes.item(i)));
					connectionInfoMap.put(info.name, info);
				}
				
				// read DatabaseConfigInfo
				DatabaseConfigInfo databaseConfigInfo = null;
				Node node = (Node) xpath.evaluate("/sqlConfig/databaseConfig", doc, XPathConstants.NODE);
				if (node != null)
				{
					databaseConfigInfo = new DatabaseConfigInfo();
					Map<String,String> attrs = _getXMLAttributes(node);
					databaseConfigInfo.copyFrom(attrs);
				}
				
				// detect old version
				_oldVersionDetected = databaseConfigInfo != null
					&& databaseConfigInfo.dataConfigTable != null
					&& databaseConfigInfo.dataConfigTable.length() != 0;
				
				// commit values only after everything succeeds
				_connectionInfoMap = connectionInfoMap;
				_databaseConfigInfo = databaseConfigInfo;
				_lastMod = lastMod;
				// reset admin connection when config changes
				resetAdminConnection();
			}
			catch (Exception e)
			{
				throw new RemoteException("Unable to load connection config file", e);
			}
		}
	}
	
	private void _save() throws RemoteException
	{
		// we can't save until the old data has been migrated
		if (_oldVersionDetected)
			throw new RemoteException("Unable to save connection config because old data hasn't been migrated yet.");
		
		try
		{
			// reset admin connection when config changes
			resetAdminConnection();
			
			Document doc = XMLUtils.getXMLFromString("<sqlConfig/>");
			Node rootNode = doc.getDocumentElement();
			Element element;

			// write DatabaseConfigInfo
			if (_databaseConfigInfo != null)
			{
				element = doc.createElement("databaseConfig");
				_setXMLAttributes(element, _databaseConfigInfo.getPropertyMap());
				rootNode.appendChild(element);
			}

			// write all ConnectionInfo, sorted by name
			List<String> names = new LinkedList<String>(getConnectionInfoNames());
			Collections.sort(names);
			for (String name : names)
			{
				element = doc.createElement("connection");
				_setXMLAttributes(element, _connectionInfoMap.get(name).getPropertyMap());
				rootNode.appendChild(element);
			}
			
			// get file paths
			String dtdPath = _file.getParentFile().getAbsolutePath() + '/' + DTD_FILENAME;
			String filePath = _file.getAbsolutePath();
			
			if (_oldVersionDetected)
			{
				// save backup of old files
				FileUtils.copy(dtdPath, dtdPath + ".old");
				FileUtils.copy(filePath, filePath + ".old");
				
				_oldVersionDetected = false;
			}
			
			// save new files
			FileUtils.copy(DTD_EMBEDDED.openStream(), new FileOutputStream(dtdPath));
			XMLUtils.getStringFromXML(rootNode, DTD_FILENAME, filePath);
		}
		catch (Exception e)
		{
			throw new RemoteException("Unable to save connection config file", e);
		}
	}
	
	public ConnectionInfo getConnectionInfo(String name) throws RemoteException
	{
		try
		{
			return getConnectionInfo(name, null, null);
		}
		catch (WeaveAuthenticationException e)
		{
			// should not happen
			throw new RemoteException("Unexpected error. WeaveAuthenticationException should only occur when using pass-through authentication.", e);
		}
	}
	public ConnectionInfo getConnectionInfo(String name, String dsUser, String dsPass) throws RemoteException, WeaveAuthenticationException
	{
		_load();
		ConnectionInfo original = _connectionInfoMap.get(name);
		if (original == null)
			return null;
		
		ConnectionInfo copy = new ConnectionInfo(dsUser, dsPass);
		copy.copyFrom(original);
		
		// test connection
		if (dsUser != null || dsPass != null)
		{
			Connection conn = null;
			try
			{
				conn = copy.getConnection();
			}
			catch (RemoteException e)
			{
				e.printStackTrace();
				return null;
			}
			finally
			{
				SQLUtils.cleanup(conn);
			}
		}
				
		return copy;
	}
	public void saveConnectionInfo(ConnectionInfo connectionInfo) throws RemoteException
	{
		connectionInfo.validate();
		
		_load();
		ConnectionInfo copy = new ConnectionInfo();
		copy.copyFrom(connectionInfo);
		_connectionInfoMap.put(connectionInfo.name, copy);
		_save();
	}
	public void removeConnectionInfo(String name) throws RemoteException
	{
		_load();
		_connectionInfoMap.remove(name);
		_save();
	}
	public Collection<String> getConnectionInfoNames() throws RemoteException
	{
		_load();
		return _connectionInfoMap.keySet();
	}
	public DatabaseConfigInfo getDatabaseConfigInfo() throws RemoteException
	{
		_load();
		if (_databaseConfigInfo == null)
			return null;
		DatabaseConfigInfo copy = new DatabaseConfigInfo();
		copy.copyFrom(_databaseConfigInfo);
		return copy;
	}
	public void setDatabaseConfigInfo(DatabaseConfigInfo info) throws RemoteException
	{
		_load();
		if (!_connectionInfoMap.containsKey(info.connection))
			throw new RemoteException(String.format("Connection named \"%s\" does not exist.", info.connection));
		if (info.schema == null || info.schema.length() == 0)
			throw new RemoteException("Schema must be specified.");
		
		if (_databaseConfigInfo == null)
			_databaseConfigInfo = new DatabaseConfigInfo();
		_databaseConfigInfo.copyFrom(info);
		_save();
	}
    
	/**
	 * This class contains all the information related to where the
	 * configuration should be stored in a database.
	 */
	static public class DatabaseConfigInfo
	{
		public DatabaseConfigInfo()
		{
		}
		
		/**
		 * If using SQLite, this will make sure the schema name is set to the default SQLite schema name.
		 */
		public void validateSchema()
		{
			try
			{
				if (Strings.equal(SQLUtils.getDbmsFromConnectString(this.connection), SQLUtils.SQLITE))
					this.schema = SQLUtils.DEFAULT_SQLITE_DATABASE;
			}
			catch (RemoteException e)
			{
				// won't happen
			}
		}
		
		public void copyFrom(Map<String,String> other)
		{
			this.connection = other.get("connection");
			this.schema = other.get("schema");
			validateSchema();
			
			String idFieldsStr = other.get("idFields");
			if (!Strings.isEmpty(idFieldsStr))
				this.idFields = CSVParser.defaultParser.parseCSVRow(idFieldsStr, true);
			else
				this.idFields = null;
			
			geometryConfigTable = other.get("geometryConfigTable");
			dataConfigTable = other.get("dataConfigTable");
		}
		public void copyFrom(DatabaseConfigInfo other)
		{
			this.connection = other.connection;
			this.schema = other.schema;
			validateSchema();
			this.idFields = other.idFields;
			this.geometryConfigTable = other.geometryConfigTable;
			this.dataConfigTable = other.dataConfigTable;
		}
		public Map<String,String> getPropertyMap()
		{
			Map<String,String> result = MapUtils.fromPairs(
				"connection", connection,
				"schema", schema
			);
			if (idFields != null && idFields.length > 0)
				result.put("idFields", CSVParser.defaultParser.createCSVRow(idFields, false));
			return result;
		}
		
		/**
		 * The name of the connection (in the xml configuration) which allows
		 * connection to the database which contains the configurations
		 * (columns->SQL queries, and geometry collections).
		 */
		public String connection;
		public String schema;
		public String[] idFields;
		
		@Deprecated public String geometryConfigTable;
		@Deprecated public String dataConfigTable;
	}

	/**
	 * This class contains all the information needed to connect to a SQL
	 * database.
	 */
	static public class ConnectionInfo
	{
		public static final String DIRECTORY_SERVICE = "Directory Service";
		
		public ConnectionInfo()
		{
		}
		
		/**
		 * Constructs a ConnectionInfo object that overrides user/pass info and appends dsUser as a subfolder after folderName.
		 * @param dsUser
		 * @param dsPass
		 */
		public ConnectionInfo(String dsUser, String dsPass)
		{
			this.dsUser = dsUser;
			this.dsPass = dsPass;
		}
		
		public void validate() throws RemoteException
		{
			String missingField = null;
			if (Strings.isEmpty(name))
				missingField = "name";
			else if (Strings.isEmpty(pass) && !Strings.equal(name, DIRECTORY_SERVICE))
				missingField = "password";
			else if (Strings.isEmpty(connectString))
				missingField = "connectString";
			if (missingField != null)
				throw new RemoteException(String.format("Connection %s must be specified", missingField));
		}

		public void copyFrom(Map<String,String> other)
		{
			this.name = other.get("name");
			this.pass = other.get("pass");
			this.folderName = other.get("folderName");
			this.connectString = other.get("connectString");
			this.is_superuser = other.get("is_superuser").equalsIgnoreCase("true");
			
			validateDSInfo();
			
			// backwards compatibility
			if (connectString == null || connectString.length() == 0)
			{
				String dbms = other.get("dbms");
				String ip = other.get("ip");
				String port = other.get("port");
				String database = other.get("database");
				String user = other.get("user");
				this.connectString = SQLUtils.getConnectString(dbms, ip, port, database, user, pass);
			}
		}
		
		public void copyFrom(ConnectionInfo other)
		{
			this.name = other.name;
			this.pass = other.pass;
			this.folderName = other.folderName;
			this.connectString = other.connectString;
			this.is_superuser = other.is_superuser;
			
			validateDSInfo();
		}
		
		private void validateDSInfo()
		{
			if (this.dsUser == null && this.dsPass == null)
				return;
			
			this.name = dsUser;
			this.pass = dsPass;
			this.folderName += "/" + dsUser;
			this.is_superuser = false;
		}

		public Map<String,String> getPropertyMap()
		{
			return MapUtils.fromPairs(
				"name", name,
				"pass", pass,
				"folderName", folderName,
				"connectString", connectString,
				"is_superuser", is_superuser ? "true" : "false"
			);
		}
		
		private String dsUser = null;
		private String dsPass = null;
		public String name = "";
		public String pass = "";
		public String folderName = "";
		public String connectString = "";
		public boolean is_superuser = false;
		
		public Connection getStaticReadOnlyConnection() throws RemoteException, WeaveAuthenticationException
		{
			if (requiresAuthentication())
				throw new WeaveAuthenticationException("Authentication required");
			
			return SQLUtils.getStaticReadOnlyConnection(connectString, dsUser, dsPass);
		}

		public Connection getConnection() throws RemoteException, WeaveAuthenticationException
		{
			if (requiresAuthentication())
				throw new WeaveAuthenticationException("Authentication required");
			
			return SQLUtils.getConnection(connectString, dsUser, dsPass);
		}
		
		public boolean requiresAuthentication()
		{
			return Strings.equal(name, DIRECTORY_SERVICE);
		}
		
		public boolean usingDirectoryService()
		{
			return requiresAuthentication() || dsUser != null || dsPass != null;
		}
	}
}
